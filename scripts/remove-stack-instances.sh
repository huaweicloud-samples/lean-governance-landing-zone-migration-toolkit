#!/usr/bin/env bash
# ============================================================================
# 栈集实例交接移除
# ============================================================================
# 把某个账号的基线资源所有权从「栈集下发」转到「本地 Terraform 管理」，
# 移除栈集实例但**保留底层资源**。
#
# 这一步是整套迁移里风险最高的动作：若连带删除了底层资源，
# 账号内的网络与日志基线会立即中断，业务随之停摆。
#
# 因此执行顺序必须是：
#   1. 先把该账号的基线资源接管进本地 Terraform 状态（此时资源已脱离栈集生命周期）
#   2. 再移除栈集实例（此时栈集不再持有这些资源）
#   3. 校验资源仍然存在
#
# 跳过第 1 步直接执行第 2 步，等于让栈集连同资源一起删掉。
#
# 用法：
#   ./remove-stack-instances.sh --stack-set <栈集名> --account-id <账号ID> --regions <区域1,区域2>
# ============================================================================

set -euo pipefail

STACK_SET_NAME=""
ACCOUNT_ID=""
REGIONS=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stack-set) STACK_SET_NAME="$2"; shift 2 ;;
        --account-id) ACCOUNT_ID="$2"; shift 2 ;;
        --regions) REGIONS="$2"; shift 2 ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$STACK_SET_NAME" || -z "$ACCOUNT_ID" || -z "$REGIONS" ]]; then
    echo "用法: $0 --stack-set <栈集名> --account-id <账号ID> --regions <区域1,区域2>" >&2
    exit 1
fi

echo "=== 栈集实例交接移除 ==="
echo "栈集:   $STACK_SET_NAME"
echo "账号:   $ACCOUNT_ID"
echo "区域:   $REGIONS"
echo ""
echo "⚠ 本操作移除栈集实例。"
echo "  执行前必须确认该账号的基线资源已被接管进本地 Terraform 状态，"
echo "  否则资源会随实例一并消失。"
echo ""

read -rp "确认该账号资源已完成接管？输入 yes 继续: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "已取消。"
    exit 1
fi

echo ""
echo "--- 移除前：记录栈集实例 ---"
python3 "$SCRIPT_DIR/rfs_stack_instance.py" list --stack-set "$STACK_SET_NAME" || true

echo ""
echo "--- 移除栈集实例 ---"
python3 "$SCRIPT_DIR/rfs_stack_instance.py" delete \
    --stack-set "$STACK_SET_NAME" \
    --account-ids "$ACCOUNT_ID" \
    --regions "$REGIONS"

echo ""
echo "--- 移除后：确认实例已消失 ---"
python3 "$SCRIPT_DIR/rfs_stack_instance.py" list --stack-set "$STACK_SET_NAME" || true

echo ""
echo "=== 移除完成 ==="
echo ""
echo "请立即校验底层资源仍然存在："
echo "  python3 $SCRIPT_DIR/verify-account-resources.py --region <区域> \\"
echo "      --expect-vpc <基线VPC网段> --expect-subnet <基线子网网段> --expect-flow-log"
