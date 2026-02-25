#!/bin/bash
#
# AMS OpenCode 部署和调试脚本
#
pwdir=`pwd`

amsworkdir="/home/acnet/ams-ai/ams-work"
binworkdir="${amsworkdir}/bin-work"
projectdir="/home/acnet/ams-ai/ams-opencode"

. ${binworkdir}/_console_config.par
. ${binworkdir}/_console_global.sh

cd $projectdir

# 确保 bun 版本与 package.json 中 packageManager 字段一致
ensure_bun() {
    required=$(grep '"packageManager"' package.json | sed 's/.*"bun@\([^"]*\)".*/\1/')
    export PATH="$HOME/.bun/bin:$PATH"
    current=$(bun --version 2>/dev/null || echo "none")
    if [ "$current" = "$required" ]; then
        echo "✓ bun@${required} 已就绪"
        return
    fi
    echo "⏳ 安装 bun@${required} (当前: ${current})..."
    curl -fsSL https://bun.sh/install | bash -s "bun-v${required}"
    export PATH="$HOME/.bun/bin:$PATH"
    echo "✓ bun@$(bun --version)"
}
# 构建项目
do_build() {
    ensure_bun
    # 安装依赖
    echo "🚀 安装依赖..."
    bun install
    # 构建所有平台二进制（含 linux-x64，用于部署到 ams-ai）
    echo "⏳ 正在构建 opencode (含 linux-x64)..."
    echo "bun run build : 构建所有平台独立二进制"
    cd packages/opencode
    bun run build
    cd $projectdir

    echo "✅ 项目构建完成. 产物: packages/opencode/dist/"
}
# 精简构建（仅 ubuntu-24 / windows / ventura 标准变体，排除 musl 和 baseline）
do_build_slim() {
    ensure_bun
    echo "🚀 安装依赖..."
    bun install
    # --targets=linux,windows,darwin : 各 OS 的标准变体（共 5 个）
    #   opencode-linux-x64       (ubuntu-24 amd64)
    #   opencode-linux-arm64     (linux arm64)
    #   opencode-darwin-arm64    (ventura Apple Silicon)
    #   opencode-darwin-x64      (ventura Intel)
    #   opencode-windows-x64     (windows)
    echo "⏳ 精简构建 opencode (linux + windows + darwin 标准变体)..."
    cd packages/opencode
    bun run build -- --targets=linux,windows,darwin
    cd $projectdir

    echo "✅ 精简构建完成. 产物: packages/opencode/dist/"
}
# 本机安装（将 linux-x64 二进制安装到 /usr/local/bin）
do_install_local() {
    binary="${projectdir}/packages/opencode/dist/opencode-linux-x64/bin/opencode"
    if [ ! -f "${binary}" ]; then
        echo "❌ 构建产物不存在，请先运行: $0 build-slim"
        exit 1
    fi
    echo "⏳ 安装 opencode 到 /usr/local/bin/opencode ..."
    sudo cp "${binary}" /usr/local/bin/opencode
    sudo chmod +x /usr/local/bin/opencode
    echo "✅ 安装完成"
    opencode --version
}
# ========================================
# 复制到目标节点
# ========================================
do_copy() {
    [ -n "$1" ] && serverip="$1"

    dorm=$2
    # 复制前清除目录下全部子目录和文件
    [ "${dorm}" = "true" ] && echo "清除 ${projectdir}@${serverip} ..." && ssh acnet@${serverip} -C "rm -rf ${projectdir}/*"

    cd ${projectdir}
    # 指定备份路径 : 同步过程中没有文件被覆盖则不会触发备份
    backupdir="/home/acnet/work/ams-opencode-$(date +%Y%m%d%H%M%S)"
    echo "⏳ 复制 ${projectdir} 到 acnet@${serverip}:${projectdir} ..."
    echo "被覆盖的文件备份到 : ${backupdir}"
    # --exclude='node_modules'                        : 排除依赖，服务端 bun install 重新安装
    # --exclude='packages/opencode/dist/*darwin*'     : 排除 macOS 构建产物（与 Linux 不兼容）
    # --exclude='packages/opencode/dist/*windows*'    : 排除 Windows 构建产物
    doeval "rsync -azvh \
     --exclude='.git' \
     --exclude='node_modules' \
     --exclude='packages/opencode/dist/*darwin*' \
     --exclude='packages/opencode/dist/*windows*' \
     --backup --backup-dir=${backupdir} -e ssh ${projectdir}/ acnet@${serverip}:${projectdir}/"
}
# ========================================
# 主命令分发
# ========================================
case "$1" in
    # 远程部署
    copy) do_copy "$2" "$3" ;;
    build) do_build ;;
    build-slim) do_build_slim ;;
    install-local) do_install_local ;;
    *)
        echo "$0 copy [IP] [true]   - 复制到远程主机，true=清除目标目录"
        echo "$0 build              - 安装依赖并构建项目 (全部 11 个平台)"
        echo "$0 build-slim         - 精简构建 (linux + windows + darwin 标准变体，共 5 个)"
        echo "$0 install-local      - 安装 linux-x64 二进制到 /usr/local/bin/opencode"
    ;;
esac

cd $pwdir
