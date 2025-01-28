#!/bin/bash

export FF_DRIVER_NAME=cflow
export SRC_DIR=/benchmark/cflow-1.6

tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark

export FUZZ_DIR=/binary/ffafl

# step 1, generating .bc file, you can use wllvm or similar approach as you wish
# -fsanitize=address：启用 AddressSanitizer，这是一个内存错误检测工具。
# -flto：启用链接时优化(Link Time Optimization)，这允许编译器在整个程序范围内进行优化。
# -fuse-ld=gold：指定使用 gold 链接器，它比默认的 bfd 链接器更快，并且支持更多的优化。
# -Wl,-plugin-opt=save-temps：传递给链接器的选项，保存中间文件(如 .bc 文件)以便后续分析或调试。
# -Wno-unused-command-line-argument：忽略未使用的命令行参数警告。
export CC=clang 
export CFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
export CXX=clang++ 
export CXXFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
cd $SRC_DIR && ./configure --with-shared=no && make -j$(nproc)

# step 2, coverage instrumentation and analysis
# 在这个阶段，使用 LLVM 的 opt 工具对生成的 .bc 文件应用各种插件进行覆盖率检测和分析。
export PREFUZZ=/FishFuzz/
export TMP_DIR=$PWD/TEMP_$FF_DRIVER_NAME
export ADDITIONAL_COV="-load $PREFUZZ/afl-llvm-pass.so -test -outdir=$TMP_DIR -pmode=conly"
# -load $PREFUZZ/afl-llvm-pass.so：加载 AFL（American Fuzzy Lop）的 LLVM pass 插件，该插件用于模糊测试。
# -test, -outdir=$TMP_DIR, -pmode=conly：这些是插件特定的选项，用于控制其行为。
export ADDITIONAL_ANALYSIS="-load $PREFUZZ/afl-llvm-pass.so -test -outdir=$TMP_DIR -pmode=aonly"
export BC_PATH=$(find . -name "$FF_DRIVER_NAME.0.5.precodegen.bc" -printf "%h\n")/
mkdir -p $TMP_DIR
opt $ADDITIONAL_COV $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc -o $BC_PATH$FF_DRIVER_NAME.final.bc 
opt $ADDITIONAL_ANALYSIS $BC_PATH$FF_DRIVER_NAME.final.bc -o $BC_PATH$FF_DRIVER_NAME.temp.bc

# step 3, static distance map calculation
# 在此步骤中，通过生成调用图并运行 Python 脚本来计算静态距离映射。
# 使用 opt 工具生成调用图，并将其输出为 .dot 文件格式。
opt -dot-callgraph $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc && mv $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc.callgraph.dot $TMP_DIR/dot-files/callgraph.dot
# 运行自定义脚本以根据调用图生成初始的距离映射。
$PREFUZZ/scripts/gen_initial_distance.py $TMP_DIR

# step 4, generating final target\
# 最后一步涉及使用 AFL 或其他模糊测试工具链来生成最终的可执行文件。
# 指定功能模式、函数 ID 文件路径以及输出目录。
export ADDITIONAL_FUNC="-pmode=fonly -funcid=$TMP_DIR/funcid.csv -outdir=$TMP_DIR"
export CC=$PREFUZZ/afl-clang-fast
export CXX=$PREFUZZ/afl-clang-fast++
# 查找适合当前架构的 AddressSanitizer 库。
export ASAN_LIBS=$(find `llvm-config --libdir` -name libclang_rt.asan-`uname -m`.a |head -n 1)
# 链接额外的库，包括动态链接库、线程库、实时库和数学库。
export EXTRA_LDFLAGS="-ldl -lpthread -lrt -lm"
$CC $ADDITIONAL_FUNC $BC_PATH$FF_DRIVER_NAME.final.bc -o $FF_DRIVER_NAME.fuzz $EXTRA_LDFLAGS $ASAN_LIBS

mv $TMP_DIR $FUZZ_DIR/
mv $FF_DRIVER_NAME.fuzz $FUZZ_DIR/$FF_DRIVER_NAME


# Build ffapp binary

cd && rm -r $SRC_DIR/ && tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark
export FUZZ_DIR=/binary/ffapp

# step 1, generating .bc file, you can use wllvm or similar approach as you wish
export CC=clang 
export CFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
export CXX=clang++ 
export CXXFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
cd $SRC_DIR && ./configure --with-shared=no && make -j$(nproc)

# step 2, coverage instrumentation and analysis
export PREFUZZ=/Fish++/
export TMP_DIR=$PWD/TEMP_$FF_DRIVER_NAME
export ADDITIONAL_RENAME="-load $PREFUZZ/afl-fish-pass.so -test -outdir=$TMP_DIR -pmode=rename"
export ADDITIONAL_COV="-load $PREFUZZ/SanitizerCoveragePCGUARD.so -cov"
export ADDITIONAL_ANALYSIS="-load $PREFUZZ/afl-fish-pass.so -test -outdir=$TMP_DIR -pmode=aonly"
export BC_PATH=$(find . -name "$FF_DRIVER_NAME.0.5.precodegen.bc" -printf "%h\n")/
mkdir -p $TMP_DIR
opt $ADDITIONAL_RENAME $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc -o $BC_PATH$FF_DRIVER_NAME.rename.bc 
opt $ADDITIONAL_COV $BC_PATH$FF_DRIVER_NAME.rename.bc -o $BC_PATH$FF_DRIVER_NAME.cov.bc 
opt $ADDITIONAL_ANALYSIS $BC_PATH$FF_DRIVER_NAME.rename.bc -o $BC_PATH$FF_DRIVER_NAME.temp.bc

# step 3, static distance map calculation
opt -dot-callgraph $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc && mv $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc.callgraph.dot $TMP_DIR/dot-files/callgraph.dot
$PREFUZZ/scripts/gen_initial_distance.py $TMP_DIR


# step 4, generating final target
export ADDITIONAL_FUNC="-pmode=fonly -funcid=$TMP_DIR/funcid.csv -outdir=$TMP_DIR"
export CC=$PREFUZZ/afl-fish-fast
export CXX=$PREFUZZ/afl-fish-fast++
export ASAN_LIBS=$(find `llvm-config --libdir` -name libclang_rt.asan-`uname -m`.a |head -n 1)
export EXTRA_LDFLAGS="-ldl -lpthread -lrt -lm"
$CC $ADDITIONAL_FUNC $BC_PATH$FF_DRIVER_NAME.cov.bc -o $FF_DRIVER_NAME.fuzz $EXTRA_LDFLAGS $ASAN_LIBS

mv $TMP_DIR $FUZZ_DIR/
mv $FF_DRIVER_NAME.fuzz $FUZZ_DIR/$FF_DRIVER_NAME

unset CFLAGS CXXFLAGS

# build afl binary
cd && rm -r $SRC_DIR/ && tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark

export FUZZ_DIR=/binary/afl
export CC="/AFL/afl-clang-fast -fsanitize=address"
export CXX="/AFL/afl-clang-fast++ -fsanitize=address"
cd $SRC_DIR && ./configure --with-shared=no && make -j$(nproc)
mv $(find . -name $FF_DRIVER_NAME -printf "%h\n")/$FF_DRIVER_NAME $FUZZ_DIR/

# build afl++ binary
cd && rm -r $SRC_DIR/ && tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark

export FUZZ_DIR=/binary/aflpp
export CC="/AFL++/afl-clang-fast -fsanitize=address"
export CXX="/AFL++/afl-clang-fast++ -fsanitize=address"
cd $SRC_DIR && ./configure --with-shared=no && make -j$(nproc)
mv $(find . -name $FF_DRIVER_NAME -printf "%h\n")/$FF_DRIVER_NAME $FUZZ_DIR/


# build neutral binary 
cd && rm -r $SRC_DIR/ && tar xzf /benchmark/source/cflow-1.6.tar.gz -C /benchmark
export CC=clang 
export CFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
export CXX=clang++ 
export CXXFLAGS="-fsanitize=address -flto -fuse-ld=gold -Wl,-plugin-opt=save-temps -Wno-unused-command-line-argument"
cd $SRC_DIR && ./configure --with-shared=no && make -j$(nproc)

export FUZZ_DIR=/binary/neutral
export CC=/AFL/afl-clang-fast
export CXX=/AFL/afl-clang-fast++
export ASAN_LIBS=$(find `llvm-config --libdir` -name libclang_rt.asan-`uname -m`.a |head -n 1)
export EXTRA_LDFLAGS="-ldl -lpthread -lrt -lm"
$CC $BC_PATH$FF_DRIVER_NAME.0.5.precodegen.bc -o $FF_DRIVER_NAME.neutral $EXTRA_LDFLAGS $ASAN_LIBS
mv $FF_DRIVER_NAME.neutral $FUZZ_DIR/$FF_DRIVER_NAME

