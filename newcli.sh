#!/bin/bash
set -euo pipefail

# 最小脚本：创建新项目，启用 Generative Language 与 Vertex AI，仅输出项目ID

ensure_dep() {
    command -v "$1" >/dev/null 2>&1 || { echo "缺少依赖: $1" >&2; exit 1; }
}

ensure_gcp_login() {
    ensure_dep gcloud
    if ! gcloud config get-value account >/dev/null 2>&1; then
        echo "未检测到已登录的 GCP 账户，请先执行: gcloud auth login" >&2
        exit 1
    fi
}

new_project_id() {
    local prefix="${PROJECT_PREFIX:-gemini-pro}"
    local rand
    rand=$(openssl rand -hex 4)
    echo "${prefix}-$(date +%s)-${rand}" | cut -c1-30
}

main() {
    ensure_dep openssl
    ensure_gcp_login

    local project_id
    project_id=$(new_project_id)

    # 创建项目（日志走 stderr，stdout 仅回显 project_id）
    gcloud projects create "$project_id" --name="$project_id" --quiet >&2

    # 等待项目变为 ACTIVE（处理资源传播延迟）
    local state
    for i in $(seq 1 "${PROJECT_READY_RETRY:-20}"); do
        state=$(gcloud projects describe "$project_id" --format="value(lifecycleState)" 2>/dev/null || true)
        if [ "$state" = "ACTIVE" ]; then
            break
        fi
        sleep 2
    done
    if [ "$state" != "ACTIVE" ]; then
        echo "项目未就绪，当前状态: ${state:-UNKNOWN}" >&2
        exit 1
    fi

    # 启用 Gemini 相关 API（Generative Language 与 Vertex AI）
    enable_service_with_retry() {
        local svc="$1"
        local pid="$2"
        local max_attempts="${MAX_RETRY:-8}"
        local base_delay="${BASE_DELAY_SEC:-2}"
        local attempt=1
        while true; do
            # 单个服务启用，减少一次性突发
            out=$(gcloud services enable "$svc" --project="$pid" --quiet 2>&1)
            rc=$?
            if [ $rc -eq 0 ]; then
                echo "已启用服务: $svc" >&2
                return 0
            fi
            # 已启用也视为成功
            if echo "$out" | grep -qi "already enabled\|ALREADY_EXISTS"; then
                echo "服务已处于启用状态: $svc" >&2
                return 0
            fi
            # 429 速率限制，指数回退 + 抖动
            if echo "$out" | grep -q "RESOURCE_EXHAUSTED\|RATE_LIMIT_EXCEEDED\|Quota exceeded"; then
                if [ $attempt -ge $max_attempts ]; then
                    echo "启用服务失败(超出最大重试): $svc" >&2
                    echo "$out" >&2
                    return 1
                fi
                delay=$(( base_delay * (2 ** (attempt - 1)) ))
                # 抖动 0-1000ms
                sleep_sec=$(awk -v d="$delay" 'BEGIN{srand(); printf("%.3f", d + rand())}')
                echo "速率受限，重试第 ${attempt}/${max_attempts} 次，等待 ${sleep_sec}s: $svc" >&2
                sleep "$sleep_sec"
                attempt=$((attempt + 1))
                continue
            fi
            # 其他错误，有限重试
            if [ $attempt -ge $max_attempts ]; then
                echo "启用服务失败(超出最大重试): $svc" >&2
                echo "$out" >&2
                return 1
            fi
            sleep 2
            attempt=$((attempt + 1))
        done
    }

    enable_service_with_retry generativelanguage.googleapis.com "$project_id" || exit 1
    enable_service_with_retry aiplatform.googleapis.com "$project_id" || exit 1

    # 仅输出项目ID
    echo "$project_id"
}

main "$@"
