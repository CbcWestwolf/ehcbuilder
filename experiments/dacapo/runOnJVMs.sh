#!/bin/zsh

# 检查参数
if [[ $# == 0 ]] {
  echo "USAGE: dir"
  echo "请输入 mutants 所在的目录"
  exit 1
}

source config.sh
setopt +o nomatch
root=$PWD

args=(-Xcomp -Xint)
otherJvms=(OpenJ9_OpenJDK11 Zulu_OpenJDK11 GraalVM_OpenJDK11)

for mutantsDir ($*) {

  # 初始化变量
  resultDir=$mutantsDir"_result"    # 不同 JVM 运行结果所在的文件夹
  [ ! -d $resultDir ] && mkdir $resultDir
  argsLog=$root/$resultDir/cmp_args.log
  jvmsLog=$root/$resultDir/cmp_jvms.log
  noverifyLog=$root/$resultDir/cmp_noverify.log
  rm $argsLog $jvmsLog $noverifyLog >/dev/null 2>&1

  if [[ ! -d $mutantsDir ]] {
    echo $mutantsDir'不存在'
    exit 1
  }

  cd $mutantsDir
  for num ($(ls .)) {
    [ ! -d $num ] && continue # 跳过非目录的文件
    [ ! -d $root/$resultDir/$num ] && mkdir $root/$resultDir/$num
    cd $num

    rm -rf scratch sootOutput >/dev/null 2>&1
    for dir ($(ls .)) {
      [ ! -d $dir ] && continue
      [[ $dir != $DacapoDir* ]] && continue
      [ -d $root/$resultDir/$num/$dir ] && continue
      
      # 1. 跑各个 JVM

      echo "----------- $mutantsDir ----------- $num ----------- $dir -----------"
      mkdir $root/$resultDir/$num/$dir

      cd $dir
      rm -rf scratch _DTJVM.log run.log >/dev/null 2>&1
      for ((i = 1; i <= $#jvms; ++i)) {
        
        if [[ $jvms[$i] == HotSpot* ]] { # 如果是 HotSpot，需要执行4次

          # 先跑默认参数 (-Xmixed)
          echo $jvms[$i]
          timeout $TIMEOUT"s" $jvmPaths[$i] -cp .:$DacapoLib Harness $DacapoArg >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]_DTJVM.log
          }
          rm -rf scratch >/dev/null 2>&1

          for arg ($hotspotArgs) { # 然后跑3个带参数的: -Xint, -Xcomp, -noverify
            echo $jvms[$i] $arg
            timeout $TIMEOUT"s" $jvmPaths[$i] -cp .:$DacapoLib $arg Harness $DacapoArg >run.log 2>&1
            if [[ $? == 124 ]] {
              echo "Timeout!"
              echo "Infinite Loop" > _DTJVM.log
            }
            [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]"$arg"_run.log
            if [[ -f _DTJVM.log ]] {
              java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
              mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]"$arg"_DTJVM.log
            }
            rm -rf scratch >/dev/null 2>&1
          }

        } else {                         # 其它 JVM 只执行一次就行

          # 先正常执行
          echo $jvms[$i]
          timeout $TIMEOUT"s" $jvmPaths[$i] -cp .:$DacapoLib Harness $DacapoArg >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]_DTJVM.log
          }
          rm -rf scratch >/dev/null 2>&1

          # 再执行 -noverify
          echo $jvms[$i] -noverify
          timeout $TIMEOUT"s" $jvmPaths[$i] -cp .:$DacapoLib -noverify Harness $DacapoArg >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]-noverify_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]-noverify_DTJVM.log
          }
          rm -rf scratch >/dev/null 2>&1
        }
      }

      rm -f core.*.dmp Snap.*.trc jitdump.*.dmp javacore.*.txt >/dev/null 2>&1 # 这个 core dump 信息占用空间极大

      cd .. # cd $dir

      # 2. compare 结果，如果没有不同，直接删除跑出来的 log
      # Tips: 可以用  cmp -b 或者 diff -q 来比较两份文件, 比较之后 $? == 0 说明相同， $? == 1 说明不同

      if [[ ! -f $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_DTJVM.log ]] {
        # HotSpot 默认模式没有结果，直接跳过，并输出提示信息
        echo "No $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_DTJVM.log"
        continue
      }

      hasDiff=0
      # 2.1 比较 HotSpot 默认模式和 -graal, -Xcomp, -Xint 的区别
      for arg ($args) {
        if [[ ! -f $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_DTJVM.log ]] {
          echo -e 'No $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_DTJVM.log\n' >> $argsLog
        } else {
          # # 临时: 删掉 _DTJVM.log 中的 @106...
          # sed -i '/^@106/d' HotSpot_OpenJDK11"$arg"_DTJVM.log
          # java -cp $TOOL script.LogFormatter HotSpot_OpenJDK11"$arg"_DTJVM.log HotSpot_OpenJDK11"$arg"_DTJVM.log

          info=$(diff -q $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_DTJVM.log $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_DTJVM.log)
          if [[ $? == 1 ]] {
            echo $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_DTJVM.log >> $argsLog
            hasDiff=1
          } else {
            rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_DTJVM.log >/dev/null 2>&1
            rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11"$arg"_run.log >/dev/null 2>&1
          }
        }
      }

      # 2.2 比较 HotSpot 默认模式和 OpenJ9, Zulu, GraalVM 默认模式的区别
      for jvm ($otherJvms) {
        if [[ ! -f $root/$resultDir/$num/$dir/$jvm"_DTJVM.log" ]] {
          echo -e 'No $root/$resultDir/$num/$dir/$jvm"_DTJVM.log"\n' >> $jvmsLog
        } else {

          info=$(diff -q $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_DTJVM.log $root/$resultDir/$num/$dir/$jvm"_DTJVM.log")
          if [[ $? == 1 ]] {
            echo $root/$resultDir/$num/$dir/$jvm"_DTJVM.log" >> $jvmsLog
            hasDiff=1
          } else {
            rm $root/$resultDir/$num/$dir/$jvm"_DTJVM.log" >/dev/null 2>&1
            rm $root/$resultDir/$num/$dir/$jvm"_run.log" >/dev/null 2>&1
          }
        }
      }
      if (( $hasDiff == 0 )) {
        rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_DTJVM.log >/dev/null 2>&1
        rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11_run.log >/dev/null 2>&1
      }

      hasDiff=0
      if [[ ! -f $root/$resultDir/$num/$dir/HotSpot_OpenJDK11-noverify_DTJVM.log ]] {
        # HotSpot 默认模式没有结果，直接跳过，并输出提示信息
        echo "No $root/$resultDir/$num/$dir/HotSpot_OpenJDK11-noverify_DTJVM.log"
        continue
      }
      # 2.3 比较 HotSpot -noverify 和 OpenJ9, Zulu, GraalVM -noverify 的区别
      for jvm ($otherJvms) {
        if [[ ! -f $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log" ]] {
          echo -e 'No $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log"\n' >> $noverifyLog
        } else {

          info=$(diff -q $root/$resultDir/$num/$dir/HotSpot_OpenJDK11-noverify_DTJVM.log $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log")
          if [[ $? == 1 ]] {
            echo $num $dir $jvm"-noverify_DTJVM.log" >> $noverifyLog
            hasDiff=1
          } else {
            rm $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log" >/dev/null 2>&1
            rm $root/$resultDir/$num/$dir/$jvm"-noverify_run.log" >/dev/null 2>&1
          }
        }
      }
      if (( $hasDiff == 0 )) {
        rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11-noverify_DTJVM.log >/dev/null 2>&1
        rm $root/$resultDir/$num/$dir/HotSpot_OpenJDK11-noverify_run.log >/dev/null 2>&1
      }
    }

    cd .. # cd $num
  }

  cd .. # cd $mutantsDir
}