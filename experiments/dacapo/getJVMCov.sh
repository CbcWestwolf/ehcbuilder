#!/bin/zsh

# 输入：策略目录列表

# 0. 加载配置文件
# set -e
source config.sh

projectDir='<path-to-baseline-hotspot>'
srcDir="$projectDir"'src/'
javaApp="$projectDir"'build/linux-x86_64-normal-server-release/images/jdk/bin/java'

# 对每个策略，获取其最高 EHC 的所有变种的累计覆盖率
for mutantsDir ($*) {
  cd $mutantsDir
  echo "============== $mutantsDir ============="

  rm *.info >/dev/null 2>&1

  # a) Resetting counters, remove all .gcda files
  lcov -z -d "$projectDir" >/dev/null 2>&1

  # b) create baseline coverage data file
  lcov -c -i -d "$projectDir" -b "$srcDir" -o base.info --ignore-errors graph >/dev/null 2>&1

  for num ($(ls .)) {
    [ ! -d $num ] && continue # 跳过非目录的文件
    cd $num

    # 获取所有最深的叶子节点的 JVM 覆盖率
    # for dir ($(java -cp $TOOL script.GetDeepestLeaves $DacapoDir)) {
    for dir ($(ls .)) {
      [ ! -d $dir ] && continue
      [[ $dir != $DacapoDir* ]] && continue
      echo "============== $mutantsDir ============= $num ============= $dir ============="
      # 解除插桩
      cp -r $dir sootOutput
      java -cp $TOOL mutation.Uninstrument $dir

      # 运行最后生成的（可变异的）变种，看看其JVM覆盖率提升程度如何

      # -Xmixed
      timeout -s KILL $TIMEOUT"s" $javaApp -cp sootOutput:$DacapoLib Harness "$DacapoArg" >/dev/null 2>&1
      if [[ $? == 137 ]] {
        echo "timeout!"
      }
      rm -rf scratch >/dev/null 2>&1

      # "-Xint" 
      timeout -s KILL $((TIMEOUT*3))"s" $javaApp -cp sootOutput:$DacapoLib -Xint Harness "$DacapoArg" >/dev/null 2>&1
      if [[ $? == 137 ]] {
        echo "timeout!"
      }
      rm -rf scratch >/dev/null 2>&1

      # "-Xcomp" 
      timeout -s KILL $((TIMEOUT*10))"s" $javaApp -cp sootOutput:$DacapoLib -Xcomp Harness "$DacapoArg" >/dev/null 2>&1
      if [[ $? == 137 ]] {
        echo "timeout!"
      }
      rm -rf scratch >/dev/null 2>&1

      # "-noverify"
      timeout -s KILL $TIMEOUT"s" $javaApp -cp sootOutput:$DacapoLib -noverify Harness "$DacapoArg" >/dev/null 2>&1
      if [[ $? == 137 ]] {
        echo "timeout!"
      }
      rm -rf scratch >/dev/null 2>&1

      rm -rf sootOutput >/dev/null 2>&1
    }

    cd .. # cd $num
  }

  # c) Capturing the current coverage state to a file
  # 不加 --ignore-errors graph 的话，会因为缺少 gcno 文件而无法执行
  lcov -c -d "$projectDir" -b "$srcDir" -o test.info --ignore-errors graph >/dev/null 2>&1

  # d) combine baseline and test coverage data
  covInfo=$(lcov -a base.info -a test.info -o coverage.info) >/dev/null 2>&1

  # 获取这一行输出的覆盖率并通过 echo 返回
  lineCov=$(echo $covInfo | grep lines)
  funcCov=$(echo $covInfo | grep functions)
  branCov=$(echo $covInfo | grep branches)
  lineCov=${lineCov%\%*} # 去除 % 及其右边的字符
  lineCov=${lineCov#*\:} # 去除 : 及其左边的字符
  funcCov=${funcCov%\%*}
  funcCov=${funcCov#*\:}
  branCov=${branCov%\%*}
  branCov=${branCov#*\:}
  echo "$mutantsDir total lineCov: $lineCov, funcCov: $funcCov, branCov: $branCov" 

  # 用这条命令过滤出需要的文件夹：
  covInfo=$(filterInfo coverage.info coverage.filter.info)

  genhtml coverage.info --output-directory lcov_report --ignore-errors source >/dev/null 2>&1
  genhtml coverage.filter.info --output-directory lcov_filter_report --ignore-errors source >/dev/null 2>&1

  # 获取这一行输出的覆盖率并通过 echo 返回
  lineCov=$(echo $covInfo | grep lines)
  funcCov=$(echo $covInfo | grep functions)
  branCov=$(echo $covInfo | grep branches)
  lineCov=${lineCov%\%*} # 去除 % 及其右边的字符
  lineCov=${lineCov#*\:} # 去除 : 及其左边的字符
  funcCov=${funcCov%\%*}
  funcCov=${funcCov#*\:}
  branCov=${branCov%\%*}
  branCov=${branCov#*\:}
  echo "$mutantsDir part lineCov: $lineCov, funcCov: $funcCov, branCov: $branCov" 

  echo "==========================="

  cd .. # cd $mutantsDir
}