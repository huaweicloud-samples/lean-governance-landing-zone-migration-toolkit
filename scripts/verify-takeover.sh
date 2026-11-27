#!/usr/bin/env bash
# ============================================================================
# 接管零漂移校验
# ============================================================================
# 接管既有基线资源后，必须确认 Terraform 侧的定义与线上实际状态一致：
# 只应有「待接管」的条目，不应出现任何新增、变更或删除。
#
# 期望输出：
#   Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.
#
# 若出现 to change 或 to destroy，说明资源定义与线上状态存在属性差异。
# 此时**不要**直接 apply —— apply 会用本地定义覆盖线上配置。
# 正确做法是修正定义中的属性，使其与线上一致后重新校验。
#
# 用法：
#   ./verify-takeover.sh [terraform工作目录]
# ============================================================================

set -euo pipefail

TF_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../infra" && pwd)}"

echo "=== 接管零漂移校验 ==="
echo "工作目录: $TF_DIR"
echo ""

cd "$TF_DIR"

PLAN_FILE="$(mktemp)"
trap 'rm -f "$PLAN_FILE"' EXIT

echo "--- 1. 生成 plan ---"
terraform plan -input=false -out="$PLAN_FILE" 2>&1 | tee /dev/stderr | tail -5
echo ""

echo "--- 2. 解析变更计数 ---"
COUNTS="$(terraform show -json "$PLAN_FILE" | python3 -c '
import json, sys
data = json.load(sys.stdin)
rc = data.get("resource_changes", [])
add = sum(1 for r in rc if r.get("change", {}).get("actions") == ["create"])
chg = sum(1 for r in rc if r.get("change", {}).get("actions") == ["update"])
del_ = sum(1 for r in rc if r.get("change", {}).get("actions") == ["delete"])
imp = sum(1 for r in rc if r.get("change", {}).get("actions") == ["no-op"]
          and r.get("importing", {}).get("id"))
rep = sum(1 for r in rc if "delete" in r.get("change", {}).get("actions", [])
          and "create" in r.get("change", {}).get("actions", []))
print(f"{add} {chg} {del_} {imp} {rep}")
')"

read -r ADD CHG DEL IMP REP <<< "$COUNTS"

echo "待接管 (to import): $IMP"
echo "待新增 (to add):    $ADD"
echo "待变更 (to change): $CHG"
echo "待删除 (to destroy): $DEL"
echo "需重建 (replace):   $REP"
echo ""

if [[ "$ADD" != "0" || "$CHG" != "0" || "$DEL" != "0" || "$REP" != "0" ]]; then
    echo "✗ 校验未通过：存在非接管类变更"
    echo ""
    echo "  · 待新增条目说明本地定义多声明了线上不存在的资源，请移除"
    echo "  · 待变更 / 需重建条目说明本地定义与线上状态存在属性差异，请逐项对齐"
    echo "  · 特别检查：标签、加密配置、描述、是否启用等易漂移字段"
    echo ""
    echo "在差异消除前不要执行 apply。"
    exit 1
fi

if [[ "$IMP" == "0" ]]; then
    echo "⚠ 提示：本次 plan 没有接管条目"
    echo "  若预期接管的对象尚未被接管，请检查 import 块是否已启用、资源标识是否填写"
    exit 1
fi

echo "✓ 校验通过：$IMP 个对象待接管，其余无任何变更"
echo ""
echo "下一步：terraform apply -auto-approve  （接管不会重建或删除资源）"
