#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo -e "${BOLD}Usage:${NC} ./deploy.sh [backend|frontend|all]"
  echo ""
  echo "  backend   Deploy cimplur-core to ECS"
  echo "  frontend  Deploy fyli-fe-v2 to S3/CloudFront"
  echo "  all       Deploy both (backend first, then frontend)"
  echo ""
  echo "Examples:"
  echo "  ./deploy.sh backend"
  echo "  ./deploy.sh frontend"
  echo "  ./deploy.sh all"
  exit 1
}

deploy_backend() {
  echo -e "${BLUE}${BOLD}=== Deploying Backend (cimplur-core) ===${NC}"

  echo -e "${BLUE}Authenticating with ECR...${NC}"
  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 116134826460.dkr.ecr.us-east-1.amazonaws.com

  echo -e "${BLUE}Building Docker image...${NC}"
  docker build --platform linux/amd64 -t fyli-core -f "$ROOT_DIR/cimplur-core/Memento/Memento/Dockerfile" "$ROOT_DIR/cimplur-core/Memento"

  echo -e "${BLUE}Tagging image...${NC}"
  docker tag fyli-core:latest 116134826460.dkr.ecr.us-east-1.amazonaws.com/fyli-core:latest

  echo -e "${BLUE}Pushing to ECR...${NC}"
  docker push 116134826460.dkr.ecr.us-east-1.amazonaws.com/fyli-core:latest

  echo -e "${BLUE}Updating ECS service...${NC}"
  aws ecs update-service --region us-east-1 --cluster fyli-ecs-cluster --service apis-service-fyli-8080 --force-new-deployment > /dev/null

  echo -e "${GREEN}${BOLD}Backend deployed successfully${NC}"
}

deploy_frontend() {
  echo -e "${BLUE}${BOLD}=== Deploying Frontend (fyli-fe-v2) ===${NC}"

  echo -e "${BLUE}Building frontend...${NC}"
  cd "$ROOT_DIR/fyli-fe-v2"
  npm run build

  echo -e "${BLUE}Syncing to S3...${NC}"
  aws s3 sync ./dist s3://app.fyli.com --acl public-read

  echo -e "${BLUE}Invalidating CloudFront cache...${NC}"
  aws cloudfront create-invalidation --distribution-id E1T07DEHPF8CVT --paths "/*" > /dev/null

  cd "$ROOT_DIR"
  echo -e "${GREEN}${BOLD}Frontend deployed successfully${NC}"
}

if [ $# -eq 0 ]; then
  usage
fi

case "$1" in
  backend)
    deploy_backend
    ;;
  frontend)
    deploy_frontend
    ;;
  all)
    deploy_backend
    echo ""
    deploy_frontend
    ;;
  *)
    echo -e "${RED}Unknown target: $1${NC}"
    usage
    ;;
esac

echo ""
echo -e "${GREEN}${BOLD}Deploy complete!${NC}"
