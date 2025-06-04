#!/bin/bash

# deepfilternet_fix Build Script for Python 3.12 (修复版本)
# 构建支持Python 3.12的deepfilternet_fix包

set -e  # 遇到错误时退出

echo "🚀 正在构建 deepfilternet_fix for Python 3.12..."

# 获取绝对路径避免路径问题
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 设置环境变量
export PYTHON_VERSION=${PYTHON_VERSION:-"3.12"}
export BUILD_DIR="$SCRIPT_DIR/build"
export DIST_DIR="$SCRIPT_DIR/dist"
export WHEELS_DIR="$SCRIPT_DIR/wheels"

# 优化编译设置
export JOBS=${JOBS:-$(nproc)}
export CARGO_INCREMENTAL=1

# 设置快速链接器
if command -v lld >/dev/null 2>&1; then
    export RUSTFLAGS="-C link-arg=-fuse-ld=lld"
    echo "🔧 使用 lld 快速链接器"
elif command -v mold >/dev/null 2>&1; then
    export RUSTFLAGS="-C link-arg=-fuse-ld=mold"  
    echo "🔧 使用 mold 快速链接器"
fi

# 清理之前的构建
echo "🧹 清理之前的构建文件..."
rm -rf "$DIST_DIR" "$BUILD_DIR" "$SCRIPT_DIR"/*.egg-info/
rm -rf "$PROJECT_ROOT/pyDF/dist" "$PROJECT_ROOT/pyDF/build" "$PROJECT_ROOT/pyDF"/*.egg-info/
rm -rf "$PROJECT_ROOT/pyDF-data/dist" "$PROJECT_ROOT/pyDF-data/build" "$PROJECT_ROOT/pyDF-data"/*.egg-info/
rm -rf "$WHEELS_DIR"
mkdir -p "$WHEELS_DIR"

# 检查依赖项
echo "🔍 检查构建依赖项..."
command -v cargo >/dev/null 2>&1 || { echo "❌ 错误: 需要安装 Rust/Cargo" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "❌ 错误: 需要安装 Python 3" >&2; exit 1; }

# 安装Python构建依赖
echo "📦 安装构建依赖..."
python3 -m pip install --upgrade pip maturin poetry wheel setuptools build

# 检查Python版本
PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "🐍 当前Python版本: $PYTHON_VER，使用 $JOBS 个并行任务"

# 1. 并行构建 Rust 组件
echo "⚡ 1. 并行构建 Rust 组件..."

# 并行构建 DeepFilterLib
(
    echo "   🔨 构建 DeepFilterLib (pyDF)..."
    cd "$PROJECT_ROOT/pyDF"
    maturin build --release --jobs $JOBS --out "$WHEELS_DIR"
    echo "   ✅ DeepFilterLib 构建完成"
) &
PID1=$!

# 并行构建 DeepFilterDataLoader  
(
    echo "   🔨 构建 DeepFilterDataLoader (pyDF-data)..."
    cd "$PROJECT_ROOT/pyDF-data"
    maturin build --release --jobs $JOBS --out "$WHEELS_DIR"
    echo "   ✅ DeepFilterDataLoader 构建完成"
) &
PID2=$!

# 等待两个构建任务完成
echo "   ⏳ 等待 Rust 组件构建完成..."
wait $PID1 $PID2
echo "🎉 所有 Rust 组件构建完成"

# 回到工作目录
cd "$SCRIPT_DIR"

# 3. 安装本地构建的wheel包作为依赖
echo "📥 3. 安装本地构建的依赖包..."
DEEPFILTERLIB_WHEEL=$(find "$WHEELS_DIR" -name "DeepFilterLib-*.whl" | head -1)
DEEPFILTERDATALOADER_WHEEL=$(find "$WHEELS_DIR" -name "DeepFilterDataLoader-*.whl" | head -1)

if [ -n "$DEEPFILTERLIB_WHEEL" ]; then
    echo "   📦 安装 DeepFilterLib: $(basename "$DEEPFILTERLIB_WHEEL")"
    python3 -m pip install "$DEEPFILTERLIB_WHEEL" --force-reinstall
else
    echo "❌ 错误: 未找到 DeepFilterLib wheel文件" >&2
    exit 1
fi

if [ -n "$DEEPFILTERDATALOADER_WHEEL" ]; then
    echo "   📦 安装 DeepFilterDataLoader: $(basename "$DEEPFILTERDATALOADER_WHEEL")"
    python3 -m pip install "$DEEPFILTERDATALOADER_WHEEL" --force-reinstall
    HAS_DATALOADER=1
else
    echo "   ⚠️ 未找到 DeepFilterDataLoader wheel文件，跳过训练功能"
    HAS_DATALOADER=0
fi

# 4. 准备构建配置
echo "⚙️ 4. 准备deepfilternet_fix构建配置..."
cp pyproject.toml pyproject.toml.backup

# 添加本地依赖到pyproject.toml
cat >> pyproject.toml << 'EOF'

# 本地构建的依赖项（构建时添加）
deepfilterlib = "*"
EOF

# 如果找到了DataLoader，也添加它
if [ "$HAS_DATALOADER" = "1" ]; then
    cat >> pyproject.toml << 'EOF'
deepfilterdataloader = { version = "*", optional = true }
EOF
    # 更新extras以包含train依赖
    sed -i 's/train = \["icecream"\]/train = ["deepfilterdataloader", "icecream"]/' pyproject.toml
fi

# 5. 构建 deepfilternet_fix
# echo "🏗️ 5. 构建 deepfilternet_fix Python包..."
# python3 -m build --wheel --outdir "$DIST_DIR"
echo "🏗️ 5. 构建 deepfilternet_fix Python包 (.whl + .tar.gz)..."
python3 -m build --outdir "$DIST_DIR"

# 恢复原始配置文件
mv pyproject.toml.backup pyproject.toml

# 6. 验证构建结果
echo "🔍 6. 验证构建结果..."
DEEPFILTERNET_FIX_WHEEL=$(find "$DIST_DIR" -name "deepfilternet_fix-*.whl" | head -1)

if [ -n "$DEEPFILTERNET_FIX_WHEEL" ]; then
    echo "✅ deepfilternet_fix 构建成功: $(basename "$DEEPFILTERNET_FIX_WHEEL")"
    
    echo ""
    echo "🎉 构建完成！"
    echo "📁 输出文件:"
    echo "   - deepfilternet_fix: $(basename "$DEEPFILTERNET_FIX_WHEEL")"
    echo "   - DeepFilterLib: $(basename "$DEEPFILTERLIB_WHEEL")"
    [ "$HAS_DATALOADER" = "1" ] && echo "   - DeepFilterDataLoader: $(basename "$DEEPFILTERDATALOADER_WHEEL")"
    echo ""
    echo "📋 安装命令:"
    echo "   pip install \"$DEEPFILTERNET_FIX_WHEEL\""
    
else
    echo "❌ deepfilternet_fix 构建失败" >&2
    exit 1
fi