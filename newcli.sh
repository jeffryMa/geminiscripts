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

create_project_with_retry() {
    local project_id="$1"
    local max_attempts="${CREATE_MAX_RETRY:-8}"
    local base_delay="${BASE_DELAY_SEC:-2}"
    local attempt=1

    local parent_args=()
    if [ -n "${FOLDER_ID:-}" ]; then
        parent_args+=("--folder=${FOLDER_ID}")
    elif [ -n "${ORG_ID:-}" ]; then
        parent_args+=("--organization=${ORG_ID}")
    else
        # 自动探测单一组织，若仅有一个可见组织则默认挂载到该组织
        local orgs
        orgs=$(gcloud organizations list --format='value(name)' 2>/dev/null || true)
        if [ -n "$orgs" ]; then
            local org_count
            org_count=$(echo "$orgs" | wc -l | tr -d ' ')
            if [ "$org_count" = "1" ]; then
                local org_name
                org_name=$(echo "$orgs" | head -n1)
                local org_id
                org_id=${org_name#organizations/}
                if [ -n "$org_id" ]; then
                    parent_args+=("--organization=${org_id}")
                    echo "检测到单一组织(${org_id})，将项目创建在该组织下" >&2
                fi
            fi
        fi
    fi

    while true; do
        out=$(gcloud projects create "$project_id" --name="$project_id" "${parent_args[@]}" --quiet 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "项目创建成功: ${project_id}" >&2
            return 0
        fi

        # 如果项目ID已被占用，生成新ID并继续（不增加 attempt 次数）
        if echo "$out" | grep -qi "already exists\|already in use"; then
            project_id=$(new_project_id)
            echo "项目ID已被占用，改用: ${project_id}" >&2
            continue
        fi

        # 429/配额/速率限制，指数回退
        if echo "$out" | grep -q "RESOURCE_EXHAUSTED\|RATE_LIMIT_EXCEEDED\|Quota exceeded"; then
            if [ $attempt -ge $max_attempts ]; then
                echo "创建项目失败(超出最大重试)" >&2
                echo "$out" >&2
                return 1
            fi
            delay=$(( base_delay * (2 ** (attempt - 1)) ))
            sleep_sec=$(awk -v d="$delay" 'BEGIN{srand(); printf("%.3f", d + rand())}')
            echo "创建受限，重试第 ${attempt}/${max_attempts} 次，等待 ${sleep_sec}s" >&2
            sleep "$sleep_sec"
            attempt=$((attempt + 1))
            continue
        fi

        # 其他错误，有限重试
        if [ $attempt -ge $max_attempts ]; then
            echo "创建项目失败(超出最大重试)" >&2
            echo "$out" >&2
            return 1
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
}

main() {
    ensure_dep openssl
    ensure_gcp_login

    local project_id
    project_id=$(new_project_id)

    # 创建项目（带重试与可选父级）
    if ! create_project_with_retry "$project_id"; then
        exit 1
    fi

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

    # 不进行结算账号绑定，直接启用所需 API

    # 启用 Gemini 相关 API（Service Usage、Resource Manager、Vertex AI、Generative Language、Gemini for Google Cloud）
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
            # 服务在区域/租户不可用或不存在，视为可跳过（非致命）
            if echo "$out" | grep -qi "not found\|Requested entity was not found\|unsupported\|Invalid resource name"; then
                echo "服务不可用或不存在，跳过: $svc" >&2
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

    enable_service_with_retry serviceusage.googleapis.com "$project_id" || exit 1
    enable_service_with_retry cloudresourcemanager.googleapis.com "$project_id" || exit 1
    enable_service_with_retry aiplatform.googleapis.com "$project_id" || exit 1
    enable_service_with_retry generativelanguage.googleapis.com "$project_id" || exit 1
    enable_service_with_retry cloudaicompanion.googleapis.com "$project_id" || exit 1
    # 兼容别名/区域命名：Gemini Cloud Assist（若不存在将被跳过）
    enable_service_with_retry geminicloudassist.googleapis.com "$project_id" || exit 1

    # 验证 Gemini for Google Cloud 是否已启用
    if ! gcloud services list --enabled --project="$project_id" --format='value(config.name)' | grep -q '^cloudaicompanion.googleapis.com$'; then
        echo "Gemini for Google Cloud 未能启用，可能需要组织/管理员在控制台产品页手动开通或授予权限。" >&2
        echo "可在控制台搜索 'Gemini for Google Cloud' 产品并点击启用，或联系组织管理员。" >&2
        exit 1
    fi

    # 仅输出项目ID
    echo "$project_id"
}

main "$@"
