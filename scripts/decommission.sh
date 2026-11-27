#!/usr/bin/env bash
# ============================================================================
# 旧治理机制退役序列
# ============================================================================
# 按固定顺序拆除旧机制，每一步都留出观察期：
#
#   第 1 步  停用自动化下发（先止血，不再产生新的实例）
#   观察期  2-4 周
#   第 2 步  移除空栈集实例
#   第 3 步  删除栈集定义
#   第 4 步  删除残留资源栈
#   第 5 步  归档留痕（不可逆点，务必最后执行）
#
# 顺序不可颠倒：先停下发再清实例，否则清理期间新实例会再次产生，
# 形成永远清不完的循环。
#
# 第 5 步是唯一不可逆的一步 —— 归档完成后旧机制的痕迹不可恢复，
# 因此必须确认前面四步全部完成、且观察期内无异常后再执行。
#
# 用法：
#   ./decommission.sh --stack-set <栈集名> --step <1-5> [--confirm]
# ============================================================================

set -euo pipefail

STACK_SET_NAME=""
STEP=""
AUTO_CONFIRM=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="${ARCHIVE_DIR:-./decommission-archive}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stack-set) STACK_SET_NAME="$2"; shift 2 ;;
        --step) STEP="$2"; shift 2 ;;
        --confirm) AUTO_CONFIRM=true; shift ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$STACK_SET_NAME" || -z "$STEP" ]]; then
    echo "用法: $0 --stack-set <栈集名> --step <1-5> [--confirm]" >&2
    exit 1
fi

confirm_or_exit() {
    local prompt="$1"
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi
    read -rp "$prompt 输入 yes 继续: " answer
    if [[ "$answer" != "yes" ]]; then
        echo "已取消。"
        exit 1
    fi
}

case "$STEP" in
    1)
        echo "=== 第 1 步：停用自动化下发 ==="
        echo "栈集: $STACK_SET_NAME"
        echo ""
        echo "本步骤在云端控制台关闭栈集的自动下发开关后执行。"
        echo "关闭后："
        echo "  · 不再向目标账号下发新的基线实例"
        echo "  · 已存在的实例与资源保持不变"
        echo ""
        echo "请在控制台完成开关关闭后，按任意键继续。"
        confirm_or_exit "确认已关闭自动下发？"
        echo "已停用自动下发。接下来进入观察期（2-4 周）。"
        ;;

    2)
        echo "=== 第 2 步：移除空栈集实例 ==="
        echo "栈集: $STACK_SET_NAME"
        echo ""
        echo "本步骤只移除已确认完成接管的账号的栈集实例。"
        echo "请先对每个账号执行接管校验："
        echo "  ./verify-takeover.sh"
        echo ""
        confirm_or_exit "确认所有目标账号均已完成接管并通过零漂移校验？"
        echo ""
        echo "请按账号逐个执行移除："
        echo "  ./remove-stack-instances.sh --stack-set $STACK_SET_NAME \\"
        echo "      --account-id <账号ID> --regions <区域列表>"
        ;;

    3)
        echo "=== 第 3 步：删除栈集定义 ==="
        echo "栈集: $STACK_SET_NAME"
        echo ""
        echo "本步骤删除栈集本身，栈集内不再有任何实例。"
        echo ""
        confirm_or_exit "确认第 2 步已全部完成、栈集内无残留实例？"
        echo ""
        echo "请在控制台删除该栈集，或执行："
        echo "  terraform destroy -target=huaweicloud_rfs_stack_set.baseline"
        ;;

    4)
        echo "=== 第 4 步：删除残留资源栈 ==="
        echo "栈集: $STACK_SET_NAME"
        echo ""
        echo "本步骤清理旧机制遗留的资源栈定义。"
        echo ""
        echo "请在控制台「资源编排」中查找该栈集名下的残留栈并逐一删除。"
        echo "删除前请确认这些栈下的资源已全部被接管。"
        ;;

    5)
        echo "=== 第 5 步：归档留痕（不可逆） ==="
        echo "栈集: $STACK_SET_NAME"
        echo ""
        echo "⚠ 这是整个退役序列中唯一不可逆的一步。"
        echo "  归档完成后，旧机制的操作痕迹不可恢复。"
        echo ""
        echo "请确认以下四项全部满足："
        echo "  [1] 第 1-4 步已全部执行完毕"
        echo "  [2] 观察期内无治理异常告警"
        echo "  [3] 所有目标账号的基线资源对等校验通过"
        echo "  [4] 全部账号的治理标签已更新为当前治理机制"
        echo ""
        confirm_or_exit "确认四项均已满足并执行归档？"
        echo ""
        mkdir -p "$ARCHIVE_DIR"
        ARCHIVE_FILE="$ARCHIVE_DIR/decommission-$(date +%Y%m%d-%H%M%S).txt"
        {
            echo "治理机制退役归档"
            echo "=============================="
            echo "时间:     $(date '+%Y-%m-%d %H:%M:%S')"
            echo "栈集:     $STACK_SET_NAME"
            echo "执行步骤: 第 5 步（归档）"
            echo ""
            echo "退役前状态"
            echo "----------"
            python3 "$SCRIPT_DIR/rfs_stack_instance.py" list --stack-set "$STACK_SET_NAME" 2>&1 || true
        } | tee "$ARCHIVE_FILE"
        echo ""
        echo "归档已保存: $ARCHIVE_FILE"
        ;;
    *)
        echo "步骤号无效：$STEP（有效范围 1-5）" >&2
        exit 1
        ;;
esac
