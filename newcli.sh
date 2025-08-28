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

    # 启用 Gemini 相关 API（Generative Language 与 Vertex AI）
    gcloud services enable generativelanguage.googleapis.com aiplatform.googleapis.com \
        --project="$project_id" --quiet >&2

    # 仅输出项目ID
    echo "$project_id"
}

main "$@"
