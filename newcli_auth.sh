#!/bin/bash
set -eo pipefail

# Google Cloud Shell OAuth 凭证获取脚本
# 一键完成授权、生成凭证文件并下载

# 颜色定义
GREEN='\033[0;32m'
BOLD='\033[1m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# OAuth 配置
CLIENT_ID="681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
CLIENT_SECRET="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"

echo -e "${BLUE}${BOLD}🚀 Google Cloud Shell OAuth 凭证获取工具${NC}"
echo -e "${BLUE}一键完成授权、生成凭证文件并下载${NC}"
echo "============================================================"

# 检查依赖
echo -e "${YELLOW}🔍 检查系统依赖...${NC}"

check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${RED}✗ 缺少依赖: $1${NC}"
        echo -e "${YELLOW}请安装 $1 后重试${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ $1 已安装${NC}"
    fi
}

check_dependency "gcloud"
check_dependency "curl"
check_dependency "jq"

# 检查登录状态
echo -e "${YELLOW}🔍 检查 Google Cloud 登录状态...${NC}"
if ! gcloud config get-value account >/dev/null 2>&1; then
    echo -e "${RED}✗ 请先登录 Google Cloud${NC}"
    echo -e "${YELLOW}运行以下命令登录：${NC}"
    echo -e "${GREEN}gcloud auth login${NC}"
    exit 1
else
    account=$(gcloud config get-value account)
    echo -e "${GREEN}✓ 已登录账户: $account${NC}"
fi

# 获取当前项目或创建新项目
current_project=$(gcloud config get-value project 2>/dev/null || echo "")

if [ -z "$current_project" ]; then
    echo -e "${YELLOW}🔍 未检测到当前项目，正在创建新项目...${NC}"
    
    # 生成项目ID
    timestamp=$(date +%s)
    random_hex=$(openssl rand -hex 4)
    temp_project_id="gemini-pro-${timestamp}-${random_hex}"
    project_id=$(echo "$temp_project_id" | cut -c1-30)
    
    echo -e "${BLUE}项目ID: $project_id${NC}"
    
    # 创建项目
    echo -e "${YELLOW}🚀 正在创建 Google Cloud 项目...${NC}"
    gcloud projects create "$project_id" --name="$project_id" --quiet
    
    # 等待项目就绪
    echo -e "${YELLOW}⏳ 等待项目就绪...${NC}"
    while true; do
        state=$(gcloud projects describe "$project_id" --format="value(lifecycleState)" 2>/dev/null || true)
        [ "$state" = "ACTIVE" ] && break
        sleep 2
    done
    
    echo -e "${GREEN}✓ 项目已创建并激活${NC}"
    
    # 设置项目为当前活动项目
    echo -e "${YELLOW}🔧 设置项目为当前活动项目...${NC}"
    gcloud config set project "$project_id"
    
else
    echo -e "${GREEN}✓ 使用现有项目: $current_project${NC}"
    project_id="$current_project"
fi

# 启用 API
echo -e "${YELLOW}🔧 正在启用必要的 API...${NC}"
apis=("aiplatform.googleapis.com" "generativelanguage.googleapis.com" "geminicloudassist.googleapis.com")

for api in "${apis[@]}"; do
    echo "正在启用: $api"
    
    attempt=1
    max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        if gcloud services enable "$api" --quiet 2>&1; then
            echo -e "${GREEN}✓ 已启用: $api${NC}"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${YELLOW}⚠ 启用失败: $api，继续执行...${NC}"
                break
            fi
            echo "! 启用失败，${attempt}/${max_attempts} 次重试..."
            sleep $((attempt * 2))
            attempt=$((attempt + 1))
        fi
    done
    
    sleep 2
done

# 启动 OAuth 流程
echo -e "${YELLOW}🌐 正在启动 OAuth 流程...${NC}"

# 生成 OAuth 授权 URL
scope_string="https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile"
auth_url="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=http://localhost:8080&scope=$scope_string&response_type=code&access_type=offline&prompt=consent"

echo -e "${BLUE}${BOLD}OAuth 授权步骤${NC}"
echo -e "${BLUE}1. 即将在浏览器中打开授权页面${NC}"
echo -e "${BLUE}2. 请使用您的 Google 账户登录并授权${NC}"
echo -e "${BLUE}3. 授权完成后，请复制授权码${NC}"

# 在 Cloud Shell 中打开浏览器
echo -e "${YELLOW}🚀 正在打开授权页面...${NC}"
if command -v google-chrome >/dev/null 2>&1; then
    google-chrome "$auth_url" &
elif command -v firefox >/dev/null 2>&1; then
    firefox "$auth_url" &
else
    echo -e "${BLUE}请手动在浏览器中打开以下 URL：${NC}"
    echo -e "${GREEN}$auth_url${NC}"
fi

# 等待用户完成 OAuth 流程
echo -e "${BLUE}完成 OAuth 授权后，请将授权码粘贴到下方并按 Enter 键继续...${NC}"
read -p "授权码: " auth_code

if [ -z "$auth_code" ]; then
    echo -e "${RED}✗ 未提供授权码${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 已获取授权码: ${auth_code:0:20}...${NC}"

# 交换令牌
echo -e "${YELLOW}🔄 正在交换访问令牌...${NC}"

# 使用 curl 交换令牌
token_response=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "code=$auth_code" \
    -d "grant_type=authorization_code" \
    -d "redirect_uri=http://localhost:8080")

# 检查响应
if echo "$token_response" | jq -e '.access_token' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ 令牌交换成功${NC}"
else
    echo -e "${RED}✗ 令牌交换失败${NC}"
    echo "响应: $token_response"
    exit 1
fi

# 提取令牌信息
access_token=$(echo "$token_response" | jq -r '.access_token')
refresh_token=$(echo "$token_response" | jq -r '.refresh_token // empty')
expires_in=$(echo "$token_response" | jq -r '.expires_in // empty')

# 创建凭证文件
echo -e "${YELLOW}💾 正在创建 OAuth 凭证文件...${NC}"
credentials_file="oauth_creds_${project_id}.json"

# 计算过期时间
if [ -n "$expires_in" ] && [ "$expires_in" != "null" ]; then
    expiry=$(date -d "+$expires_in seconds" -Iseconds)
else
    expiry=""
fi

# 创建凭证数据
cat > "$credentials_file" << EOF
{
    "client_id": "$CLIENT_ID",
    "client_secret": "$CLIENT_SECRET",
    "token": "$access_token",
    "refresh_token": "$refresh_token",
    "scopes": [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ],
    "token_uri": "https://oauth2.googleapis.com/token",
    "project_id": "$project_id"${expiry:+$',\n    "expiry": "'$expiry'"'}
}
EOF

echo -e "${GREEN}✓ OAuth 凭证文件已创建: $credentials_file${NC}"



# 下载文件
echo -e "${YELLOW}📥 正在准备文件下载...${NC}"

# 检查是否在 Cloud Shell 中
if [ -n "$CLOUD_SHELL" ]; then
    echo -e "${GREEN}✓ 检测到 Google Cloud Shell 环境${NC}"
    echo -e "${BLUE}使用以下命令下载文件：${NC}"
    echo -e "${GREEN}cloudshell download $credentials_file${NC}"
    
    # 询问是否立即下载
    echo -e "${BLUE}是否立即下载凭证文件？(y/N): ${NC}"
    read -p "" -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在下载凭证文件...${NC}"
        cloudshell download "$credentials_file"
        echo -e "${GREEN}✓ 凭证文件下载完成${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 未检测到 Cloud Shell 环境${NC}"
    echo -e "${BLUE}请手动下载以下文件：${NC}"
    echo -e "${GREEN}$credentials_file${NC}"
fi

# 输出完成信息
echo -e "${GREEN}${BOLD}🎉 OAuth 凭证获取完成！${NC}"
echo "============================================================"
echo -e "${GREEN}${BOLD}项目ID: $project_id${NC}"
echo -e "${BLUE}凭证文件: $credentials_file${NC}"
echo -e "${YELLOW}下一步：${NC}"
echo -e "${BLUE}1. 下载凭证文件到本地${NC}"
echo -e "${BLUE}2. 将凭证文件路径设置到环境变量${NC}"
echo -e "${BLUE}3. 现在您可以使用 geminicli 了！${NC}"

# 显示凭证文件内容（隐藏敏感信息）
echo -e "${YELLOW}📄 凭证文件内容预览：${NC}"
#jq 'del(.client_secret, .token, .refresh_token)' "$credentials_file"



echo -e "${BLUE}${BOLD}✅ 所有操作完成！${NC}"
