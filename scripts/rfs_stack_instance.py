#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""资源栈集实例管理 —— 声明式创建 / 删除栈集实例。

背景
----
资源编排服务的「栈集」与「栈集部署」是两个动作：

* **栈集**（stack set）定义「一套模板 + 一组目标组织单元」；
* **栈集部署**（stack set deployment）把模板部署到**已经存在**的实例上。

实例的创建是独立动作。若只创建栈集与部署，实例不会凭空出现，
目标账号里也不会有任何资源 —— 整条多账号下发链路形同虚设。

本脚本负责补齐这一环：按目标账号与区域创建栈集实例，
轮询操作状态直到完成；删除时按账号与区域移除实例。

用法
----
    # 创建实例
    python rfs_stack_instance.py create \\
        --stack-set <栈集名称> \\
        --account-ids <账号ID1,账号ID2> \\
        --regions <区域1,区域2>

    # 删除实例
    python rfs_stack_instance.py delete \\
        --stack-set <栈集名称> \\
        --account-ids <账号ID1> \\
        --regions <区域1>

    # 查询实例
    python rfs_stack_instance.py list --stack-set <栈集名称>

环境变量
--------
    HW_ACCESS_KEY    访问密钥 ID
    HW_SECRET_KEY    访问密钥
    HW_REGION        区域，默认 cn-north-4
    HW_SECURITY_TOKEN  使用临时凭据时可选
"""

import argparse
import datetime
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from urllib.parse import urlparse

# 操作状态：完成
OPERATION_COMPLETE = "OPERATION_COMPLETE"
# 操作状态：失败
OPERATION_FAILED = "OPERATION_FAILED"
# 轮询间隔（秒）与最长等待时间（秒）
POLL_INTERVAL = 5
POLL_TIMEOUT = 900


def sign(ak, sk, method, url, body="", extra_headers=None):
    """为请求生成签名请求头。

    与通用 SigV4 的差异点：参与签名的 URI 统一以斜杠结尾；
    密钥直接用于摘要计算；待签名串不含凭据范围行。

    extra_headers 里的自定义头（如幂等用的 Client-Request-Id）
    一并参与签名，避免服务端判定请求头不完整。
    """
    parsed = urlparse(url)
    host = parsed.netloc
    uri = parsed.path if parsed.path.endswith("/") else parsed.path + "/"
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    body_hash = hashlib.sha256(body.encode("utf-8")).hexdigest() if body else hashlib.sha256(b"").hexdigest()

    headers = {"host": host, "x-sdk-date": timestamp}
    if body:
        headers["content-type"] = "application/json"
    for key, value in (extra_headers or {}).items():
        headers[key.lower()] = value

    signed_header_names = sorted(headers.keys())
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in signed_header_names)
    signed_headers = ";".join(signed_header_names)

    canonical_request = "\n".join([
        method.upper(),
        uri,
        parsed.query,
        canonical_headers,
        signed_headers,
        body_hash,
    ])
    string_to_sign = "\n".join([
        "SDK-HMAC-SHA256",
        timestamp,
        hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
    ])
    signature = hmac.new(sk.encode("utf-8"), string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    headers["Authorization"] = (
        f"SDK-HMAC-SHA256 Access={ak}, SignedHeaders={signed_headers}, Signature={signature}"
    )
    if body:
        headers["Content-Length"] = str(len(body.encode("utf-8")))
    return headers


def request(method, url, payload=None):
    """发起一次带签名的请求，返回解析后的响应体。"""
    ak = os.environ.get("HW_ACCESS_KEY")
    sk = os.environ.get("HW_SECRET_KEY")
    if not ak or not sk:
        sys.exit("缺少 HW_ACCESS_KEY / HW_SECRET_KEY 环境变量")

    body = json.dumps(payload) if payload is not None else ""
    # 资源编排服务的写操作要求带幂等键，缺失会直接被网关拒绝。
    headers = sign(ak, sk, method, url, body, {"Client-Request-Id": str(uuid.uuid4())})

    req = urllib.request.Request(url, data=body.encode("utf-8") if body else None, headers=headers, method=method)
    token = os.environ.get("HW_SECURITY_TOKEN")
    if token:
        req.add_header("X-Security-Token", token)

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        sys.exit(f"请求失败 HTTP {exc.code}: {method} {url}\n{detail}")
    except urllib.error.URLError as exc:
        sys.exit(f"请求失败：{method} {url}\n{exc}")

    return json.loads(raw) if raw.strip() else {}


def wait_operation(operation_url):
    """轮询操作状态直到完成。"""
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        meta = request("GET", operation_url)
        status = meta.get("status", "")
        if status == OPERATION_COMPLETE:
            print(f"操作完成：{operation_url}")
            return True
        if status == OPERATION_FAILED:
            sys.exit(f"操作失败：{operation_url}\n{json.dumps(meta, ensure_ascii=False, indent=2)}")
        print(f"操作进行中：{status}，{POLL_INTERVAL}s 后重试")
        time.sleep(POLL_INTERVAL)
    sys.exit(f"操作超时（>{POLL_TIMEOUT}s）：{operation_url}")


def wait_instance_state(stack_set, account_ids, regions):
    """按实例列表轮询下发状态，直到全部实例进入终态。

    创建接口有时只返回操作标识、有时直接落到实例列表里，
    这里统一以「实例状态」为准，避免出现「接口已受理但状态未跟踪」的盲区。
    """
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        instances = list_instances(stack_set)
        matched = [
            item for item in instances
            if item.get("stack_domain_id") in account_ids and item.get("region") in regions
        ]
        if matched:
            states = {item.get("status", "") for item in matched}
            if states == {OPERATION_COMPLETE}:
                print(f"栈集实例下发完成：{len(matched)} 个实例状态均为 {OPERATION_COMPLETE}")
                return True
            if OPERATION_FAILED in states:
                detail = "\n".join(
                    f"  账号={i.get('stack_domain_id')} 区域={i.get('region')} "
                    f"状态={i.get('status')} 原因={i.get('status_message', '')}"
                    for i in matched
                )
                sys.exit(f"栈集实例下发失败：\n{detail}")
        print(f"实例状态跟踪中：{[i.get('status') for i in matched] or '尚未生成实例'}，{POLL_INTERVAL}s 后重试")
        time.sleep(POLL_INTERVAL)
    sys.exit(f"等待栈集实例状态超时（>{POLL_TIMEOUT}s）")


def wait_instance_removed(stack_set, account_ids, regions):
    """等待指定账号与区域下的栈集实例从列表中消失。"""
    deadline = time.time() + POLL_TIMEOUT
    while time.time() < deadline:
        instances = list_instances(stack_set)
        matched = [
            item for item in instances
            if item.get("stack_domain_id") in account_ids and item.get("region") in regions
        ]
        if not matched:
            print("栈集实例已从列表中移除")
            return True
        print(f"实例移除中：{[i.get('status') for i in matched]}，{POLL_INTERVAL}s 后重试")
        time.sleep(POLL_INTERVAL)
    sys.exit(f"等待栈集实例移除超时（>{POLL_TIMEOUT}s）")


def build_targets(account_ids, regions):
    return {"deployment_targets": {"domain_ids": account_ids, "regions": regions}}


def api_base():
    region = os.environ.get("HW_REGION", "cn-north-4")
    return f"https://rfs.{region}.myhuaweicloud.com"


def list_instances(stack_set):
    """查询栈集实例列表。"""
    base = api_base()
    url = f"{base}/v1/stack-sets/{stack_set}/stack-instances"
    resp = request("GET", url)
    return resp.get("stack_instances") or resp.get("stackInstances") or []


def do_create(args):
    account_ids = [a.strip() for a in args.account_ids.split(",") if a.strip()]
    regions = [r.strip() for r in args.regions.split(",") if r.strip()]
    base = api_base()
    url = f"{base}/v1/stack-sets/{args.stack_set}/stack-instances"

    print(f"创建栈集实例：栈集={args.stack_set} 账号={account_ids} 区域={regions}")
    resp = request("POST", url, build_targets(account_ids, regions))
    operation_id = resp.get("operation_id") or resp.get("operationId")
    if operation_id:
        wait_operation(f"{base}/v1/stack-sets/{args.stack_set}/operations/{operation_id}/metadata")
    else:
        print("接口未返回操作 ID，改为按实例状态跟踪")
    wait_instance_state(args.stack_set, account_ids, regions)
    print("栈集实例创建完成")


def do_delete(args):
    account_ids = [a.strip() for a in args.account_ids.split(",") if a.strip()]
    regions = [r.strip() for r in args.regions.split(",") if r.strip()]
    base = api_base()
    url = f"{base}/v1/stack-sets/{args.stack_set}/stack-instances/deletion"

    print(f"删除栈集实例：栈集={args.stack_set} 账号={account_ids} 区域={regions}")
    resp = request("POST", url, build_targets(account_ids, regions))
    operation_id = resp.get("operation_id") or resp.get("operationId")
    if operation_id:
        wait_operation(f"{base}/v1/stack-sets/{args.stack_set}/operations/{operation_id}/metadata")
    else:
        print("接口未返回操作 ID，改为按实例列表跟踪")
    wait_instance_removed(args.stack_set, account_ids, regions)
    print("栈集实例删除完成")


def do_list(args):
    instances = list_instances(args.stack_set)
    if not instances:
        print("未查询到任何栈集实例")
        return
    for item in instances:
        domain = item.get("stack_domain_id") or item.get("domain_id") or "-"
        region = item.get("region") or item.get("region_id") or "-"
        status = item.get("status", "-")
        message = item.get("status_message", "")
        print(f"  账号={domain} 区域={region} 状态={status}" + (f" 说明={message}" if message else ""))
    print(f"共 {len(instances)} 个栈集实例")


def main():
    parser = argparse.ArgumentParser(description="资源栈集实例管理")
    parser.add_argument("action", choices=["create", "delete", "list"], help="操作类型")
    parser.add_argument("--stack-set", required=True, help="栈集名称")
    parser.add_argument("--account-ids", default="", help="目标账号 ID，逗号分隔")
    parser.add_argument("--regions", default="", help="目标区域，逗号分隔")
    args = parser.parse_args()

    if args.action in ("create", "delete"):
        if not args.account_ids or not args.regions:
            sys.exit("创建/删除实例需同时提供 --account-ids 与 --regions")

    {"create": do_create, "delete": do_delete, "list": do_list}[args.action](args)


if __name__ == "__main__":
    main()
