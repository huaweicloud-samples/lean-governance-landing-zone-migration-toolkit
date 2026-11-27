#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基线清单提取 —— 把声明式清单解析成可迁移的结构化清单。

输入的清单描述了每个账号收到的基线定制项；输出用于盘点「谁收到了什么、
参数是什么、覆盖哪些区域」，是接管与交接两个阶段共同的输入。

用法:
    python extract-manifest.py <清单文件路径> [json|csv]
"""

import csv
import json
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("需要 PyYAML：pip install pyyaml")


def flatten_parameters(parameters):
    """把参数字典摊平成 key=value 形式，便于 CSV 输出。"""
    if not parameters:
        return ""
    return ";".join(f"{k}={v}" for k, v in sorted(parameters.items()))


def load_manifest(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        sys.exit("清单文件格式错误：顶层应为映射结构")
    return data


def extract(data):
    """把清单展开为扁平的条目列表。"""
    entries = []
    for account in data.get("accounts", []) or []:
        account_id = account.get("account_id", "")
        account_name = account.get("name", "")
        ou = account.get("organizational_unit", "")
        for customization in account.get("customizations", []) or []:
            regions = customization.get("regions", []) or []
            entries.append({
                "account_id": account_id,
                "account_name": account_name,
                "organizational_unit": ou,
                "template": customization.get("template", ""),
                "parameters": flatten_parameters(customization.get("parameters", {})),
                "regions": ",".join(regions),
                "region_count": len(regions),
            })
    return entries


def write_json(entries):
    payload = {
        "total_accounts": len({e["account_id"] for e in entries}),
        "total_customizations": len(entries),
        "customizations": entries,
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def write_csv(entries):
    if not entries:
        print("清单为空")
        return
    writer = csv.DictWriter(sys.stdout, fieldnames=list(entries[0].keys()))
    writer.writeheader()
    writer.writerows(entries)


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: python extract-manifest.py <清单文件路径> [json|csv]")
    path = sys.argv[1]
    fmt = sys.argv[2] if len(sys.argv) > 2 else "json"

    entries = extract(load_manifest(path))
    if fmt == "csv":
        write_csv(entries)
    else:
        write_json(entries)


if __name__ == "__main__":
    main()
