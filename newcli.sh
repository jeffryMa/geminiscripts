#!/bin/bash
set -euo pipefail

# 最小脚本：创建项目，启用 Gemini 相关 API，输出项目ID

# 颜色定义
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# 检查依赖
command -v gcloud >/dev/null 2>&1 || { echo "缺少 gcloud" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "缺少 openssl" >&2; exit 1; }

# 检查登录状态
gcloud config get-value account >/dev/null 2>&1 || { echo "请先执行: gcloud auth login" >&2; exit 1; }

# 生成项目ID
project_id="${PROJECT_PREFIX:-gemini-pro}-$(date +%s)-$(openssl rand -hex 4)"
project_id=$(echo "$project_id" | cut -c1-30)

# 创建项目
gcloud projects create "$project_id" --name="$project_id" --quiet >&2

# 等待项目就绪
while true; do
    state=$(gcloud projects describe "$project_id" --format="value(lifecycleState)" 2>/dev/null || true)
    [ "$state" = "ACTIVE" ] && break
    sleep 2
done

# 启用 API
for api in aiplatform.googleapis.com generativelanguage.googleapis.com geminicloudassist.googleapis.com; do
    echo "正在启用: $api" >&2
    # 启用API，如果失败则重试
    local attempt=1
    local max_attempts=5
    while [ $attempt -le $max_attempts ]; do
        if gcloud services enable "$api" --project="$project_id" --quiet >&2 2>&1; then
            echo "✓ 已启用: $api" >&2
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                echo "✗ 启用失败: $api (已重试${max_attempts}次)" >&2
                exit 1
            fi
            echo "! 启用失败，${attempt}/${max_attempts} 次重试..." >&2
            sleep $((attempt * 2))  # 递增延迟
            attempt=$((attempt + 1))
        fi
    done
    # 每个API启用后等待，避免429
    sleep 3
done

# 输出项目ID（绿色高亮）
echo -e "${GREEN}${BOLD}$project_id${NC}"
