#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# MiBar 自动签名、打包与公证脚本
#
# 包名命名规范：<AppName>-<Version>.<ext> （例如：MiBar-1.0.dmg、MiBar-1.0.zip）
#
# 用法:
#   ./scripts/package.sh [选项]
#
# 选项:
#   --profile <profile_name>     xcrun notarytool 使用的 Keychain 凭据名称 (默认从环境变量 NOTARY_PROFILE 读取)
#   --identity <identity>        代码签名证书名称 (默认自动匹配本机 Developer ID Application)
#   --skip-notarize              跳过公证步骤，仅完成编译、签名和打包
#   --format <dmg|zip|all>       打包格式 (默认: all)
#   --output <dir>               输出目录 (默认: ./dist)
#   --help                       显示帮助信息
# ==============================================================================

# 基础配置
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MiBar"
SCHEME="MiBar"
CONFIGURATION="Release"
OUTPUT_DIR="${PROJECT_DIR}/dist"
FORMAT="all"
SKIP_NOTARIZE=false
CUSTOM_IDENTITY=""
KEYCHAIN_PROFILE="${NOTARY_PROFILE:-${AC_KEYCHAIN_PROFILE:-""}}"

# 终端彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}${BOLD}==>${NC} ${BOLD}$*${NC}"; }
success() { echo -e "${GREEN}${BOLD}✔${NC} $*"; }
warn() { echo -e "${YELLOW}${BOLD}⚠${NC} $*"; }
error() { echo -e "${RED}${BOLD}✖${NC} $*" >&2; }

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --identity)
            CUSTOM_IDENTITY="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --profile <name>      xcrun notarytool Keychain profile 名称"
            echo "  --identity <name>     代码签名证书名称 (Developer ID Application)"
            echo "  --skip-notarize       跳过公证，仅打包与签名"
            echo "  --format <dmg|zip|all> 输出文件格式 (默认: all)"
            echo "  --output <dir>        产物输出目录 (默认: ./dist)"
            echo "  --help, -h            显示此帮助信息"
            exit 0
            ;;
        *)
            error "未知参数: $1"
            exit 1
            ;;
    esac
done

cd "${PROJECT_DIR}"

# 1. 查找签名证书
info "正在检查代码签名证书..."
if [[ -n "${CUSTOM_IDENTITY}" ]]; then
    SIGNING_IDENTITY="${CUSTOM_IDENTITY}"
else
    # 优先匹配 Developer ID Application 证书
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"(Developer ID Application: .*)"/\1/' || true)
    if [[ -n "${DEVELOPER_ID}" ]]; then
        SIGNING_IDENTITY="${DEVELOPER_ID}"
    else
        warn "未找到 Developer ID Application 证书，将尝试查找 Apple Development 证书..."
        SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development:" | head -n 1 | sed -E 's/.*"(Apple Development: .*)"/\1/' || true)
    fi
fi

if [[ -z "${SIGNING_IDENTITY}" ]]; then
    error "未找到可用的代码签名证书！请在钥匙串中配置 Developer ID Application 证书或通过 --identity 指定。"
    exit 1
fi
success "使用签名证书: ${SIGNING_IDENTITY}"

# 2. 读取版本号
info "正在读取应用版本号..."
VERSION=$(xcodebuild -project "${PROJECT_DIR}/MiBar.xcodeproj" -showBuildSettings -configuration "${CONFIGURATION}" 2>/dev/null | awk -F ' = ' '/MARKETING_VERSION/ {print $2}' | tr -d '[:space:]')
if [[ -z "${VERSION}" ]]; then
    VERSION="1.0"
fi
BUILD_NUMBER=$(xcodebuild -project "${PROJECT_DIR}/MiBar.xcodeproj" -showBuildSettings -configuration "${CONFIGURATION}" 2>/dev/null | awk -F ' = ' '/CURRENT_PROJECT_VERSION/ {print $2}' | tr -d '[:space:]')
if [[ -z "${BUILD_NUMBER}" ]]; then
    BUILD_NUMBER="1"
fi

PACKAGE_BASENAME="${APP_NAME}-${VERSION}"
success "应用名称: ${APP_NAME}, 版本: ${VERSION} (Build ${BUILD_NUMBER})"
success "安装包文件名基础: ${PACKAGE_BASENAME}"

# 3. 创建临时工作区与输出目录
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_EXPORT_DIR="${BUILD_DIR}/export"
mkdir -p "${BUILD_DIR}" "${APP_EXPORT_DIR}" "${OUTPUT_DIR}"

# 4. 编译 Archive
info "正在编译并生成 Archive..."
xcodebuild clean archive \
    -project "${PROJECT_DIR}/MiBar.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    | xcbeautify 2>/dev/null || true

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
    error "Archive 构建失败，未生成 ${ARCHIVE_PATH}"
    exit 1
fi
success "Archive 生成成功: ${ARCHIVE_PATH}"

# 5. 导出 App 并进行 Hardened Runtime 签名
info "正在导出并进行 Hardened Runtime 代码签名..."
rm -rf "${APP_EXPORT_DIR}/${APP_NAME}.app"
cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${APP_EXPORT_DIR}/"
APP_PATH="${APP_EXPORT_DIR}/${APP_NAME}.app"

# 递归深度签名所有内嵌二进制与主 App
codesign --force --deep --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_PATH}"

info "正在验证应用代码签名..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
success "代码签名验证通过！"

# 6. 生成打包文件 (DMG / ZIP)
ZIP_FILE="${OUTPUT_DIR}/${PACKAGE_BASENAME}.zip"
DMG_FILE="${OUTPUT_DIR}/${PACKAGE_BASENAME}.dmg"

create_dmg() {
    local target_dmg="$1"
    local source_app="$2"
    local temp_dmg_dir="${BUILD_DIR}/dmg_temp"
    
    info "正在制作 DMG 安装镜像 (${target_dmg##*/})..."
    rm -rf "${temp_dmg_dir}" "${target_dmg}"
    mkdir -p "${temp_dmg_dir}"
    
    # 复制 App 与 Applications 软链接
    cp -R "${source_app}" "${temp_dmg_dir}/"
    ln -s /Applications "${temp_dmg_dir}/Applications"
    
    # 创建 DMG
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${temp_dmg_dir}" \
        -ov -format UDZO \
        "${target_dmg}" >/dev/null
        
    rm -rf "${temp_dmg_dir}"
    
    # 对 DMG 签名
    if [[ "${SIGNING_IDENTITY}" == *"Developer ID Application"* ]]; then
        codesign --force --sign "${SIGNING_IDENTITY}" --timestamp "${target_dmg}"
    fi
    success "DMG 创建完成: ${target_dmg}"
}

create_zip() {
    local target_zip="$1"
    local source_app="$2"
    
    info "正在制作 ZIP 压缩包 (${target_zip##*/})..."
    rm -f "${target_zip}"
    ditto -c -k --sequesterRsrc --keepParent "${source_app}" "${target_zip}"
    success "ZIP 创建完成: ${target_zip}"
}

# 7. 公证流程
if [[ "${SKIP_NOTARIZE}" == false ]]; then
    if [[ "${SIGNING_IDENTITY}" != *"Developer ID Application"* ]]; then
        warn "当前签名证书不是 Developer ID Application，Apple 公证服务仅支持 Developer ID 证书。将跳过公证。"
        SKIP_NOTARIZE=true
    elif [[ -z "${KEYCHAIN_PROFILE}" ]]; then
        warn "未检测到 NOTARY_PROFILE 环境变量，也未提供 --profile 参数。"
        warn "如果需要公证，请先执行: xcrun notarytool store-credentials \"notary-profile\" --apple-id <AppleID> --team-id <TeamID>"
        warn "然后使用: ./scripts/package.sh --profile \"notary-profile\""
        warn "本次将跳过公证步骤。"
        SKIP_NOTARIZE=true
    fi
fi

if [[ "${SKIP_NOTARIZE}" == false ]]; then
    info "正在打包公证文件..."
    NOTARY_SUBMIT_ZIP="${BUILD_DIR}/${PACKAGE_BASENAME}-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${NOTARY_SUBMIT_ZIP}"

    info "正在向 Apple Notary Service 提交公证请求 (profile: ${KEYCHAIN_PROFILE})..."
    xcrun notarytool submit "${NOTARY_SUBMIT_ZIP}" \
        --keychain-profile "${KEYCHAIN_PROFILE}" \
        --wait

    success "公证成功！正在对 App 进行票据装订 (Staple)..."
    xcrun stapler staple "${APP_PATH}"

    info "验证 Gatekeeper 评估状态..."
    spctl -a -vvv -t exec "${APP_PATH}" || true
fi

# 8. 生成最终发布产物
info "正在生成最终分发包..."
if [[ "${FORMAT}" == "dmg" || "${FORMAT}" == "all" ]]; then
    create_dmg "${DMG_FILE}" "${APP_PATH}"
    if [[ "${SKIP_NOTARIZE}" == false ]]; then
        info "正在为 DMG 装订公证票据..."
        xcrun stapler staple "${DMG_FILE}" || true
    fi
fi

if [[ "${FORMAT}" == "zip" || "${FORMAT}" == "all" ]]; then
    create_zip "${ZIP_FILE}" "${APP_PATH}"
fi

# 9. 输出结果摘要
echo ""
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}🎉 MiBar 打包完成！${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "产物目录: ${BOLD}${OUTPUT_DIR}${NC}"
echo ""

if [[ -f "${DMG_FILE}" ]]; then
    DMG_SIZE=$(ls -lh "${DMG_FILE}" | awk '{print $5}')
    DMG_SHA=$(shasum -a 256 "${DMG_FILE}" | awk '{print $1}')
    echo -e "📦 ${BOLD}DMG 安装包:${NC} ${DMG_FILE##*/}"
    echo -e "   路径: ${DMG_FILE}"
    echo -e "   大小: ${DMG_SIZE}"
    echo -e "   SHA256: ${DMG_SHA}"
    echo ""
fi

if [[ -f "${ZIP_FILE}" ]]; then
    ZIP_SIZE=$(ls -lh "${ZIP_FILE}" | awk '{print $5}')
    ZIP_SHA=$(shasum -a 256 "${ZIP_FILE}" | awk '{print $1}')
    echo -e "📦 ${BOLD}ZIP 压缩包:${NC} ${ZIP_FILE##*/}"
    echo -e "   路径: ${ZIP_FILE}"
    echo -e "   大小: ${ZIP_SIZE}"
    echo -e "   SHA256: ${ZIP_SHA}"
    echo ""
fi

echo -e "公证状态: $( [[ "${SKIP_NOTARIZE}" == false ]] && echo -e "${GREEN}已公证并装订票据${NC}" || echo -e "${YELLOW}已跳过公证${NC}" )"
echo -e "${CYAN}${BOLD}======================================================${NC}"
