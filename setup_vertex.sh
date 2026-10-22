#!/bin/bash

# 遇到错误时立即退出
set -e

echo "=========================================="
echo "   Google Cloud Vertex AI 项目与权限配置工具"
echo "=========================================="

# 1. 选择新建项目还是使用已有项目
echo "请选择操作类型:"
echo "1) 创建新 Google Cloud 项目"
echo "2) 使用已有 Google Cloud 项目"
read -p "请输入选项 (1 或 2): " choice

if [ "$choice" == "1" ]; then
    read -p "请输入新项目的 ID (必须全局唯一，例如 my-vertex-proj-$(date +%s)): " PROJECT_ID
    read -p "请输入您的结算账号 ID (Billing Account ID，格式如 XXXXXX-XXXXXX-XXXXXX): " BILLING_ACCOUNT_ID

    echo "正在创建项目: $PROJECT_ID ..."
    gcloud projects create "$PROJECT_ID"

    echo "正在为项目绑定结算账号..."
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
    
elif [ "$choice" == "2" ]; then
    echo "您当前账号下的可用项目列表："
    gcloud projects list --format="table(projectId, name)"
    echo ""
    read -p "请输入要使用的已有项目 ID: " PROJECT_ID
else
    echo "❌ 无效的选项，退出。"
    exit 1
fi

# 设置当前活动项目
echo "正在将当前项目设置为: $PROJECT_ID ..."
gcloud config set project "$PROJECT_ID"

# 2. 启用 Vertex AI 及相关 API
echo "正在启用必要的 Google Cloud API (Vertex AI, IAM 等)..."
gcloud services enable aiplatform.googleapis.com --project="$PROJECT_ID"
gcloud services enable iam.googleapis.com --project="$PROJECT_ID"
gcloud services enable cloudresourcemanager.googleapis.com --project="$PROJECT_ID"

# 3. 创建服务账号 (Service Account)
SA_NAME="vertex-sa-$(date +%s)"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
echo "正在创建服务账号: $SA_NAME ..."
gcloud iam service-accounts create "$SA_NAME" \
    --description="Service account for Vertex AI automation" \
    --display-name="Vertex AI Service Account" \
    --project="$PROJECT_ID"

# 4. 授予相关权限
echo "正在为服务账号授予 Vertex AI 用户权限 (Vertex AI User)..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/aiplatform.user"

# 5. 生成并下载/保存 JSON 密钥文件
KEY_FILE="vertex-key-$PROJECT_ID.json"
echo "正在生成服务账号 JSON 密钥文件..."
gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" \
    --project="$PROJECT_ID"

echo "=========================================="
echo " 🎉 配置全部完成！"
echo "------------------------------------------"
echo " 项目 ID:      $PROJECT_ID"
echo " 服务账号:    $SA_EMAIL"
echo " JSON 密钥路径: $(pwd)/$KEY_FILE"
echo "=========================================="
echo "提示：您可以点击 Cloud Shell 右上角的下载按钮，下载上述生成的 $KEY_FILE 文件。"
