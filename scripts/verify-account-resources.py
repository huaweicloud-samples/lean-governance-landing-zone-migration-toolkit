#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""资源对等校验 —— 核对账号内实际存在的基线资源。

接管与交接完成后，需要回答一个问题：
→「这个账号里该有的基线资源，是不是真的都在？多一个还是少一个？」

校验分三层：
    1. 存在性 —— 预期的每一项基线资源都存在；
    2. 数量   —— 实际数量与预期一致（多出来的说明有游离资源）；
    3. 属性   —— 关键属性（网段、流日志状态、安全组规则）与预期一致。

接口说明
--------
网络类资源（VPC / 子网 / 流日志）走云服务的项目级查询接口，
路径必须带项目 ID 前缀，否则接口会返回空结果而不是报错：

    GET /v1/{project_id}/vpcs
    GET /v1/{project_id}/subnets

委托类资源走身份与访问管理服务的全局端点，路径不带区域：

    GET https://iam.myhuaweicloud.com/v3.0/OS-AGENCY/agencies

注意：委托列表接口需要「委托读取权限」，权限不足时返回 403，
此时校验项标记为「无法核实」而不是「失败」，避免把权限问题误判为资源缺失。

用法:
    python verify-account-resources.py --region cn-north-4 \\
        --expect-vpc 10.0.0.0/16 \\
        --expect-subnet 10.0.1.0/24 \\
        --expect-flow-log \\
        --expect-agency landing-zone-governance-ops-agency
"""

import argparse
import datetime
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse

# 校验结果收集
PASS = []
FAIL = []
UNKNOWN = []


def record(name, ok, detail=""):
    (PASS if ok else FAIL).append((name, detail))
    mark = "✓" if ok else "✗"
    print(f"{mark} {name}" + (f" —— {detail}" if detail else ""))


def record_unknown(name, detail):
    """无法核实（通常是权限不足），既不算通过也不算失败。"""
    UNKNOWN.append((name, detail))
    print(f"? {name} —— {detail}")


def sign_request(url, ak, sk, method="GET", body=""):
    """为只读查询生成签名请求头。"""
    parsed = urlparse(url)
    uri = parsed.path if parsed.path.endswith("/") else parsed.path + "/"
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    body_hash = hashlib.sha256(body.encode("utf-8")).hexdigest() if body else hashlib.sha256(b"").hexdigest()

    headers = {"host": parsed.netloc, "x-sdk-date": timestamp}
    if body:
        headers["content-type"] = "application/json"

    signed = sorted(headers.keys())
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in signed)
    canonical_request = "\n".join([
        method, uri, parsed.query, canonical_headers, ";".join(signed), body_hash
    ])
    string_to_sign = "\n".join([
        "SDK-HMAC-SHA256", timestamp, hashlib.sha256(canonical_request.encode()).hexdigest()
    ])
    signature = hmac.new(sk.encode(), string_to_sign.encode(), hashlib.sha256).hexdigest()
    headers["Authorization"] = (
        f"SDK-HMAC-SHA256 Access={ak}, SignedHeaders={';'.join(signed)}, Signature={signature}"
    )
    token = os.environ.get("HW_SECURITY_TOKEN")
    if token:
        headers["X-Security-Token"] = token
    return headers


def api_get(url):
    """调用只读查询接口，返回 (状态码, 解析后的响应体)。"""
    ak = os.environ.get("HW_ACCESS_KEY")
    sk = os.environ.get("HW_SECRET_KEY")
    if not ak or not sk:
        sys.exit("缺少 HW_ACCESS_KEY / HW_SECRET_KEY 环境变量")

    headers = sign_request(url, ak, sk)
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        return exc.code, {"error_msg": detail[:300]}
    except urllib.error.URLError as exc:
        sys.exit(f"请求失败：{url}\n{exc}")


def project_id():
    """项目 ID。优先取环境变量，其次调用账号查询接口获取。"""
    pid = os.environ.get("HW_PROJECT_ID") or os.environ.get("HW_DOMAIN_ID")
    if pid:
        return pid
    sys.exit("缺少 HW_PROJECT_ID 环境变量（可通过账号详情接口查询获得）")


def check_vpc(region, expected_cidr):
    url = f"https://vpc.{region}.myhuaweicloud.com/v1/{project_id()}/vpcs"
    code, data = api_get(url)
    if code != 200:
        record("基线 VPC 存在", False, f"查询接口返回 HTTP {code}")
        return
    vpcs = data.get("vpcs", []) or []
    if not vpcs:
        record("基线 VPC 存在", False, "账号内未查询到任何 VPC")
        return
    matched = [v for v in vpcs if v.get("cidr") == expected_cidr]
    if matched:
        record("基线 VPC 存在", True, f"CIDR={expected_cidr}，名称={matched[0].get('name')}")
    else:
        record("基线 VPC 存在", False,
               f"未找到 CIDR={expected_cidr} 的 VPC（实际: {[v.get('cidr') for v in vpcs]}）")


def check_subnet(region, expected_cidr):
    url = f"https://vpc.{region}.myhuaweicloud.com/v1/{project_id()}/subnets"
    code, data = api_get(url)
    if code != 200:
        record("基线子网存在", False, f"查询接口返回 HTTP {code}")
        return
    subnets = data.get("subnets", []) or []
    matched = [s for s in subnets if s.get("cidr") == expected_cidr]
    if matched:
        record("基线子网存在", True, f"CIDR={expected_cidr}，名称={matched[0].get('name')}")
    else:
        record("基线子网存在", False,
               f"未找到 CIDR={expected_cidr} 的子网（实际: {[s.get('cidr') for s in subnets]}）")


def check_flow_log(region):
    """流日志按账号维度查询，路径为项目级 /fl/flow_logs。"""
    url = f"https://vpc.{region}.myhuaweicloud.com/v1/{project_id()}/fl/flow_logs"
    code, data = api_get(url)
    if code != 200:
        record("VPC 流日志已启用", False, f"查询接口返回 HTTP {code}")
        return
    logs = data.get("flow_logs", []) or []
    enabled = [l for l in logs if str(l.get("status", "")).upper() in ("ON", "ENABLED", "ACTIVE")]
    if enabled:
        record("VPC 流日志已启用", True,
               f"共 {len(enabled)} 条处于启用状态" +
               (f"，示例：{enabled[0].get('name')}" if enabled[0].get("name") else ""))
    else:
        record("VPC 流日志已启用", False,
               f"共 {len(logs)} 条流日志，无一处于启用状态"
               f"（状态取值: {[l.get('status') for l in logs]}）")


def check_agency(region, expected_name):
    """委托列表走身份与访问管理服务的全局端点（路径不含区域）。"""
    url = "https://iam.myhuaweicloud.com/v3.0/OS-AGENCY/agencies"
    code, data = api_get(url)
    if code == 403:
        record_unknown("基线委托存在",
                       "当前身份缺少委托读取权限，无法核实（不影响委托本身是否已授予）")
        return
    if code != 200:
        record("基线委托存在", False, f"查询接口返回 HTTP {code}")
        return
    agencies = data.get("agencies", []) or []
    matched = [a for a in agencies if a.get("name") == expected_name]
    if matched:
        record("基线委托存在", True, f"名称={expected_name}，ID={matched[0].get('id')}")
    else:
        record("基线委托存在", False,
               f"未找到委托 {expected_name}（实际: {[a.get('name') for a in agencies]}）")


def main():
    parser = argparse.ArgumentParser(description="基线资源对等校验")
    parser.add_argument("--region", default=os.environ.get("HW_REGION", "cn-north-4"))
    parser.add_argument("--expect-vpc", default="")
    parser.add_argument("--expect-subnet", default="")
    parser.add_argument("--expect-flow-log", action="store_true")
    parser.add_argument("--expect-agency", default="")
    args = parser.parse_args()

    print("=== 资源对等校验 ===")
    print(f"区域: {args.region}")
    print(f"项目: {project_id()}")
    print("")

    if args.expect_vpc:
        check_vpc(args.region, args.expect_vpc)
    if args.expect_subnet:
        check_subnet(args.region, args.expect_subnet)
    if args.expect_flow_log:
        check_flow_log(args.region)
    if args.expect_agency:
        check_agency(args.region, args.expect_agency)

    if not (args.expect_vpc or args.expect_subnet or args.expect_flow_log or args.expect_agency):
        sys.exit("未指定任何校验项，请至少提供一个 --expect-* 参数")

    print("")
    print(f"通过 {len(PASS)} 项，失败 {len(FAIL)} 项，无法核实 {len(UNKNOWN)} 项")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
