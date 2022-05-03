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

args=(-graal -Xcomp -Xint)
otherJvms=(OpenJ9_OpenJDK11 Zulu_OpenJDK11)

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

    rm -rf sootOutput >/dev/null 2>&1
    for dir ($(ls .)) {
      [ ! -d $dir ] && continue
      [[ $dir != scimark* ]] && continue
      [ -d $root/$resultDir/$num/$dir ] && continue

      # 1. 跑各个 JVM

      echo "----------- $mutantsDir ----------- $num ----------- $dir -----------"
      mkdir $root/$resultDir/$num/$dir

      cd $dir
      rm -rf _DTJVM.log run.log >/dev/null 2>&1
      for ((i = 1; i <= $#jvms; ++i)) {
        
        if [[ $jvms[$i] == HotSpot* ]] { # 如果是 HotSpot，需要执行4次

          # 先跑默认参数 (-Xmixed)
          echo $jvms[$i]
          timeout $TIMEOUT"s" $jvmPaths[$i] jnt.scimark2.commandline >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]_DTJVM.log
          }

          for arg ($hotspotArgs) { # 然后跑3个带参数的: -Xint, -Xcomp, -noverify
            echo $jvms[$i] $arg
            timeout $TIMEOUT"s" $jvmPaths[$i] $arg jnt.scimark2.commandline >run.log 2>&1
            if [[ $? == 124 ]] {
              echo "Timeout!"
              echo "Infinite Loop" > _DTJVM.log
            }
            [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]"$arg"_run.log
            if [[ -f _DTJVM.log ]] {
              java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
              mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]"$arg"_DTJVM.log
            }
          }

          # 然后再用 Graal 跑一下
          echo $jvms[$i] -XX:+UnlockExperimentalVMOptions -XX:+UseJVMCICompiler
          timeout $TIMEOUT"s" $jvmPaths[$i] -XX:+UnlockExperimentalVMOptions -XX:+UseJVMCICompiler jnt.scimark2.commandline >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]-graal_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]-graal_DTJVM.log
          }

        } elif [[ $jvms[$i] == ART ]] {  # ART 要用 app_process 来处理
          # TODO: 添加对 ART 的支持
          # 注意 
          # 1. dacapo 在 ART 上运行需要资源文件 ( 在 /sdcard/dacapo 中)
          # 2. scimark2 运行不需要资源文件，但在 ART 上运行极慢 ( 在 /sdcard/scimark2 中)

          # dx --dex --output=classes.dex $(find . -name "*.class") # 将所有 .class 文件转换成 dex 字节码
          # adb push classes.dex /sdcard/dacapo                     # 将 classes.dex 文件放到 /sdcard/scimark2 中
          # adb shell app_process -Djava.class.path=/sdcard/dacapo/classes.dex /sdcard/dacapo Harness $DacapoArg # 执行 dacapo
          # adb pull /sdcard/_DTJVM.log .                           # 获取 _DTJVM.log
          # adb shell rm /sdcard/_DTJVM.log
          # if [[ -f _DTJVM.log ]] {
          #   java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
          #   mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i].log
          # }

          # rm classes.dex >/dev/null 2>&1

        } else {                         # 其它 JVM 只执行一次就行

          # 先正常执行
          echo $jvms[$i]
          timeout $TIMEOUT"s" $jvmPaths[$i] jnt.scimark2.commandline >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]_DTJVM.log
          }

          # 再执行 -noverify
          echo $jvms[$i] -noverify
          timeout $TIMEOUT"s" $jvmPaths[$i] -noverify jnt.scimark2.commandline >run.log 2>&1
          if [[ $? == 124 ]] {
            echo "Timeout!"
            echo "Infinite Loop" > _DTJVM.log
          }
          [ -f run.log ] && mv run.log $root/$resultDir/$num/$dir/$jvms[$i]-noverify_run.log
          if [[ -f _DTJVM.log ]] {
            java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
            mv _DTJVM.log $root/$resultDir/$num/$dir/$jvms[$i]-noverify_DTJVM.log
          }
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

      # 2.2 比较 HotSpot 默认模式和 OpenJ9, Zulu 默认模式的区别
      for jvm ($otherJvms) {
        if [[ ! -f $root/$resultDir/$num/$dir/$jvm"_DTJVM.log" ]] {
          echo -e 'No $root/$resultDir/$num/$dir/$jvm"_DTJVM.log"\n' >> $jvmsLog
        } else {
          # # 临时: 删掉 _DTJVM.log 中的 @106...
          # sed -i '/^@106/d' $jvm"_DTJVM.log"
          # java -cp $TOOL script.LogFormatter $jvm"_DTJVM.log" $jvm"_DTJVM.log"

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
      # 2.3 比较 HotSpot -noverify 和 OpenJ9, Zulu -noverify 的区别
      for jvm ($otherJvms) {
        if [[ ! -f $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log" ]] {
          echo -e 'No $root/$resultDir/$num/$dir/$jvm"-noverify_DTJVM.log"\n' >> $noverifyLog
        } else {
          # # 临时: 删掉 _DTJVM.log 中的 @106...
          # sed -i '/^@106/d' $jvm"-noverify_DTJVM.log"
          # java -cp $TOOL script.LogFormatter $jvm"-noverify_DTJVM.log" $jvm"-noverify_DTJVM.log"

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