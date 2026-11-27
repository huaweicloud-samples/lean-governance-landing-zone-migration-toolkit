#!/usr/bin/env bash
# ============================================================================
# 基线清单提取
# ============================================================================
# 把组织统一下发的账号基线配置抽成一份可迁移的清单，
# 输出 JSON 或 CSV 两种格式。
#
# 输入是一份声明式清单文件（YAML），描述每个账号收到的定制项：
#   accounts:
#     - account_id: <账号 ID>
#       name: <账号名称>
#       organizational_unit: <所属组织单元路径>
#       customizations:
#         - template: <基线模板名>
#           parameters:
#             <参数名>: <参数值>
#           regions:
#             - <区域>
#
# 用法：
#   ./extract-manifest.sh <清单文件路径> [json|csv]
# ============================================================================

set -euo pipefail

MANIFEST_FILE="${1:-}"
OUTPUT_FORMAT="${2:-json}"

if [[ -z "$MANIFEST_FILE" ]]; then
    echo "用法: $0 <清单文件路径> [json|csv]" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo "找不到清单文件: $MANIFEST_FILE" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/extract-manifest.py" "$MANIFEST_FILE" "$OUTPUT_FORMAT"
