#!/bin/zsh

# Mutate on Mutation Forest
# Mutators Combination

# Tips: 1. 如果要使用 rsync, 一定要注意的一点是，源路径如果是一个目录的话，带上尾随斜线和不带尾随斜线是不一样的，
#         不带尾随斜线表示的是整个目录包括目录本身，带上尾随斜线表示的是目录中的文件，不包括目录本身
#         https://blog.csdn.net/qq_32706349/article/details/91451053
#       2. 使用 cp -r 复制 SRC 目录中的文件到 DEST 中的时候, 如果 DEST 不存在，则使用 cp -r SRC DEST; 如果 DEST 存在, 使用 cp -r SRC/* DEST

# 0. 加载配置文件
# set -e
source config.sh

# 1. 检查是否已经完成插桩
# 检查 $ScimarkDir"0" _DTJVM0.log id-class-method.txt 是否存在
for item ($ScimarkDir"0" _DTJVM0.log id-class-method.txt $ScimarkDir"_unins") {
  if [[ ! -e $item ]] {
    echo $item' not exist'
    exit 1
  }
}

# 在这里获取各种 base 覆盖率，用于指导变异
# 用法参考这里：https://unix.stackexchange.com/questions/460792/split-zsh-array-from-subshell-by-linebreak
array=(${(ps:\n:)"$(java -cp $TOOL script.ExceptionSceneCoverage $ScimarkDir"0" _DTJVM0.log)"})
baseStructureNum=$array[1]
baseScenarioNum=$array[2]
baseStructures=$array[3]
baseScenarios=$array[4]
echo "baseStructureNum: $baseStructureNum"
echo "baseScenarioNum: $baseScenarioNum"
echo "baseStructures: $baseStructures"
echo "baseScenarios: $baseScenarios"

rm -rf scratch >/dev/null 2>&1

# 2. 进行变异

# 创建 strategy"4" 目录
if [[ -d strategy"4" ]] {
  rm -rf strategy"4" >/dev/null 2>&1
}
mkdir strategy"4"

cd strategy"4"
for ((epoch = 1; epoch <= $EPOCH_NUM; ++epoch)) {
  [[ -d $epoch ]] && continue

  mkdir $epoch
  cd $epoch

  echo -e '\n========================= Epoch '$epoch' =========================' # -e 表示启用转义功能

  leaf=$(countLeaf $ScimarkDir $baseStructureNum)
  if [[ ! -e $ScimarkDir$baseStructureNum'.'$leaf || ! -e _DTJVM$baseStructureNum'.'$leaf.log ]] {
    echo "Copy $ScimarkRoot/$ScimarkDir0 and _DTJVM0.log to current dir"
    rm -rf $ScimarkDir$baseStructureNum'.'$leaf >/dev/null 2>&1
    cp -r $ScimarkRoot/$ScimarkDir"0" $ScimarkDir$baseStructureNum'.'$leaf
    cp "$ScimarkRoot/_DTJVM0.log" _DTJVM$baseStructureNum'.'$leaf.log
  }

  # 一个 Forest 由各个 $ScimarkDir$depth.$leaf 或者 $ScimarkDir"Test"$num 组成
  # 对于 $ScimarkDir$depth.$leaf：其中 $depth 从 0 开始，表示植入的 exception 的数量; $leaf 每一层从 0 开始，表示植入 goto 或者 Modify Exception 之后的变种
  #      $ScimarkDir$depth.$leaf 都可以作为 seed
  # $ScimarkDir"Test"$num 不能作为 seed

  curSeedNum=0                       # 作为 mutation 的种子
  curTestNum=1                       # 不作为 mutation 的种子, 但可以进行 diff testing
  timeoutCount=1000                  # 统计超时的次数，用于防止无限循环
  testThreshold=300                  # 用于 diiferential testing 的数量
  # 当 curTestNum 数量超过 testThreshold 时，停止变异
  while (( $((curSeedNum + curTestNum)) < $testThreshold && $timeoutCount > 0 )) {

    echo "-------------- epoch: $epoch,  seedNum: $curSeedNum,  testNum: $curTestNum --------------"

    # while not enough mutants for testing
    #   seed <- SampleFromForest
    #   if seed cover all ExceptionHandlingStructures {
    #     randomly select one mutators from {RethrowException, AddCause, AddSuppressed, InsertGoto, ModifyException}
    #   } else {
    #     Add ExceptionHandlingStructures
    #   }

    # 选择下个要变易的目录
    tempInfo=$(java -cp $TOOL mutation.SelectNodeOnForest $ScimarkDir)
    array=(${=tempInfo})
    if (( $#array != 2 )) {
      echo 'Not get any seed: '$tempInfo
      cd ../.. # exit $chain
      exit 1
    }
    # 选中 $ScimarkDir$selectedDepth.$selectedLeaf 进行变异
    selectedDepth=$array[1]
    selectedLeaf=$array[2]
    if [[ ! -e $ScimarkDir$selectedDepth.$selectedLeaf ]] {
      echo $ScimarkDir$selectedDepth.$selectedLeaf' not exists'
      cd ../.. # exit $chain
      exit 1
    }
    array=(${(ps:\n:)"$(java -cp $TOOL script.ExceptionSceneCoverage $ScimarkDir$selectedDepth.$selectedLeaf _DTJVM$selectedDepth.$selectedLeaf.log run$selectedDepth.$selectedLeaf.log)"})
    lastStructureNum=$array[1]
    lastScenarioNum=$array[2]
    lastStructures=$array[3]
    lastScenarios=$array[4]
    echo "Select $ScimarkDir$selectedDepth.$selectedLeaf as seed"

    # 确定 Mutators Combination 的数量
    N=$(generateRandomNum 5) # N = [0, 4]
    N=$((N+1))                # N = [1, 5]
    rm -rf lastMutant curMutant run.log scratch >/dev/null 2>&1
    cp -r $ScimarkDir$selectedDepth.$selectedLeaf curMutant
    nextSteps=(${(ps:\n:)"$(java -cp $TOOL mutation.Guidance $ScimarkDir$selectedDepth.$selectedLeaf _DTJVM$selectedDepth.$selectedLeaf.log $N)"})
    echo "nextSteps:"
    echo $nextSteps
    if (( $N != $#nextSteps )) {
      echo "脚本错误! nextSteps 数量和 $N 不一致"
      echo $N
      exit 1
    }

    for ((i = 1; i <= $N; ++i)) {
      # 以 lastMutant 为输入，输出为 curMutant
      nextStep=$nextSteps[$i]
      echo "------------------ Load $nextStep: ($i/$N) ------------------"

      rm -rf _DTJVM.log error.txt sootOutput >/dev/null 2>&1
      if [[ -e curMutant ]] {   # 说明上一轮尝试成功了, 生成了 curMutant, 可以删掉 lastMutant
        rm -rf lastMutant >/dev/null 2>&1
        mv curMutant lastMutant
      } 
      if [[ ! -e lastMutant || -e curMutant ]] {  # 如果连 lastMutant 都没有, 一定是实现的问题
        echo "lastMutant not exist, or curMutant exist"
        exit 1
      }

      echo "nextStep: "$nextStep
      if [[ ( $nextStep == *OnCaller || $nextStep == *OnSpot ) 
          && ( $nextStep == Ex* || $nextStep == Im* ) ]] { 

        # testThrow 并获取信息
        echo -e "
        testThrow: {
          Args: {
            lastIndex:        $selectedDepth.$selectedLeaf
            prefix:           $ScimarkDir,
            app:              jnt.scimark2.commandline,
            rethrow:          false
          }"
        tempInfo=$(testThrow $selectedDepth.$selectedLeaf $ScimarkDir jnt.scimark2.commandline "false")
        retVal=$? # 每一条语句都有一个返回值, 所以一定要在这里先保存返回值
        if (( $retVal == 1 )) {
          echo "Function testThrow wrong arguments"
          exit 1
        } elif (( $retVal == 2 )) {
          echo "Used up times and not found exception in error.txt"
          continue
        } 
        array=(${=tempInfo})
        if (( $#array != 4 )) {
          echo "testThrow return wrong: "$tempInfo
          continue
        }
        throwMethodID=$array[1]     # 加入 'throw' 的 methodID
        throwClassName=$array[2]    # 加入 'throw' 的类名
        throwMethodName=$array[3]   # 加入 'throw' 的函数名
        throwStmtID=$array[4]       # 加入 'throw' 的 StmtID
        echo "      
          Result: {
            throwMethodID:    $throwMethodID, 
            throwClassName:   $throwClassName, 
            throwMethodName:  $throwMethodName, 
            throwStmtID:      $throwStmtID
          }
        }"

        # 根据 error.txt 植入 throw 和 catch
        echo "
        insertThrowCatch: { 
          Args: {
            lastIndex:        $selectedDepth.$selectedLeaf
            throwClassName:   $throwClassName,
            throwMethodName:  $throwMethodName,
            throwMethodID:    $throwMethodID,
            throwStmtID:      $throwStmtID,
            prefix:           $ScimarkDir,
            useCounter:       true,
            nextStep:         $nextStep
          }"
        ThrowCatchInfo=$(
          insertThrowCatch $selectedDepth.$selectedLeaf $throwClassName \
            $throwMethodName $throwMethodID $throwStmtID $ScimarkDir "true" $nextStep
        )
        retVal=$?
        if (( $retVal == 1 )) {
          echo "error.txt shows that only one method in call stack"
          break
        } elif (( $retVal == 2 )) {
          echo "ParseWrap shows no NewException"
          continue
        } elif (( $retVal != 0 )) {
          echo "ThrowAndCatch run error"
          echo "tempInfo in testThrow $ThrowCatchInfo"
          continue
        }
        array=(${=ThrowCatchInfo})
        if (( $#array != 8 )) {
          echo "insertThrowCatch return wrong: "$ThrowCatchInfo
          continue
        }
        throwStmtID=$array[1]
        insertedStructure=$array[2]
        catchClassName=$array[3]
        catchMethodName=$array[4]
        wrapClassName=$array[5]
        wrapMethodName=$array[6]
        wrapStmtIDs=$array[7]
        chosenException=$array[8]
        echo "      
          Result: {
            throwStmtID:      $throwStmtID,
            insertedStructure:$insertedStructure
            catchClassName:   $catchClassName,
            catchMethodName:  $catchMethodName,
            wrapClassName:    $wrapClassName,
            wrapMethodName:   $wrapMethodName,
            wrapStmtIDs:      $wrapStmtIDs,
            chosenException:  $chosenException
          }
        }"

        # 将 mutate 得到的 class 文件移动到原目录中
        rm -rf temp >/dev/null 2>&1
        mv sootOutput temp
        cp -r $ScimarkDir$selectedDepth.$selectedLeaf sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $ScimarkDir$selectedDepth.$selectedLeaf 不需要加 /*
        rsync -a temp/ sootOutput
        rm -rf temp >/dev/null 2>&1
      
      } elif [[ $nextStep == "RethrowException" ]] {

        # testThrow 并获取信息
        echo -e "
        testThrow: {
          Args: {
            lastIndex:        $selectedDepth.$selectedLeaf
            prefix:           $ScimarkDir,
            app:              jnt.scimark2.commandline,
            rethrow:          true
          }"
        tempInfo=$(testThrow $selectedDepth.$selectedLeaf $ScimarkDir jnt.scimark2.commandline "true")
        retVal=$? # 每一条语句都有一个返回值, 所以一定要在这里先保存返回值
        if (( $retVal == 1 )) {
          echo "Function testThrow wrong arguments"
          exit 1
        } elif (( $retVal == 2 )) {
          echo "Used up times and not found exception in error.txt"
          continue
        } 
        array=(${=tempInfo})
        if (( $#array != 4 )) {
          echo "testThrow return wrong: "$tempInfo
          continue
        }
        throwMethodID=$array[1]     # 加入 'throw' 的 methodID
        throwClassName=$array[2]    # 加入 'throw' 的类名
        throwMethodName=$array[3]   # 加入 'throw' 的函数名
        throwStmtID=$array[4]       # 加入 'throw' 的 StmtID
        echo "
          Result: {
            throwMethodID:    $throwMethodID, 
            throwClassName:   $throwClassName, 
            throwMethodName:  $throwMethodName, 
            throwStmtID:      $throwStmtID
          }
        }"

        # 根据 error.txt 植入 throw 和 catch
        echo "
        insertThrowCatch: { 
          Args: {
            lastIndex:        $selectedDepth.$selectedLeaf
            throwClassName:   $throwClassName,
            throwMethodName:  $throwMethodName,
            throwMethodID:    $throwMethodID,
            throwStmtID:      $throwStmtID,
            prefix:           $ScimarkDir
            useCounter:       false
          }"
        ThrowCatchInfo=$(
          insertThrowCatch $selectedDepth.$selectedLeaf $throwClassName \
            $throwMethodName $throwMethodID $throwStmtID $ScimarkDir "false"
        )
        retVal=$?
        if (( $retVal == 1 )) {
          echo "error.txt shows that only one method in call stack"
          break
        } elif (( $retVal == 2 )) {
          echo "ParseWrap shows no NewException"
          continue
        } elif (( $retVal != 0 )) {
          echo "ThrowAndCatch run error"
          echo "tempInfo in testThrow $ThrowCatchInfo"
          continue
        }
        array=(${=ThrowCatchInfo})
        if (( $#array != 8 )) {
          echo "insertThrowCatch return wrong: "$ThrowCatchInfo
          continue
        }
        throwStmtID=$array[1]
        insertedStructure=$array[2]
        catchClassName=$array[3]
        catchMethodName=$array[4]
        wrapClassName=$array[5]
        wrapMethodName=$array[6]
        wrapStmtIDs=$array[7]
        chosenException=$array[8]
        echo "      
          Result: {
            throwStmtID:      $throwStmtID,
            insertedStructure:$insertedStructure
            catchClassName:   $catchClassName,
            catchMethodName:  $catchMethodName,
            wrapClassName:    $wrapClassName,
            wrapMethodName:   $wrapMethodName,
            wrapStmtIDs:      $wrapStmtIDs,
            chosenException:  $chosenException
          }
        }"

        # 将 mutate 得到的 class 文件移动到原目录中
        rm -rf temp >/dev/null 2>&1
        mv sootOutput temp
        cp -r $ScimarkDir$selectedDepth.$selectedLeaf sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $ScimarkDir$selectedDepth.$selectedLeaf 不需要加 /*
        rsync -a temp/ sootOutput
        rm -rf temp >/dev/null 2>&1

      } elif [[ $nextStep == "AddCauseAndSuppressed" ]] {

        cp -r $ScimarkDir$selectedDepth.$selectedLeaf sootOutput # 结果先暂存在 sootOutput 中

        tempInfo=$(java -cp $TOOL mutation.AddCauseOrSuppressed $ScimarkDir$selectedDepth.$selectedLeaf $selectedDepth.$selectedLeaf)
        echo $tempInfo

        if [[ $tempInfo == Error* ]] {
          continue
        }

      } elif [[ $nextStep == "InsertGoto" ]] {

        cp -r $ScimarkDir$selectedDepth.$selectedLeaf sootOutput # 结果先暂存在 sootOutput 中
        tempInfo=$(java -cp $TOOL mutation.InsertGoto $ScimarkDir$selectedDepth.$selectedLeaf $selectedDepth.$selectedLeaf "true")
        array=(${=tempInfo})
        if [[ $#array != "3" || $tempInfo == Error* ]] {
          echo "InsertGoto return "$tempInfo
          continue
        }
        selectMethodID=$array[1]
        hp=$array[2]
        tp=$array[3]
        echo -e "
        insert goto: {
          Args: {
            methodID:   $selectMethodID,
            hp:         $hp,
            tp:         $tp,
          }
        }"

      } elif [[ $nextStep == "ModifyException" ]] {

        cp -r $ScimarkDir$selectedDepth.$selectedLeaf sootOutput # 结果先暂存在 sootOutput 中
        modifyInfo=$(java -cp $TOOL mutation.ModifyException $ScimarkDir$selectedDepth.$selectedLeaf $selectedDepth.$selectedLeaf)
        array=(${=modifyInfo})
        if (( $#array < 2 || $#array > 50 )) {
          echo "ModifyException return wrong: "$modifyInfo
          continue
        }
        echo $modifyInfo
        modifyType=$array[1]
        methodID=$array[2]
        if [[ "$modifyType" == 'Error' || ! -d "sootOutput" ]] {
          continue
        }

      } else {
        echo 'Should not reach here! nextStep: '$nextStep
        exit 1
      }

      echo "Check Bodies in sootOutput"
      tempInfo=$(java -cp $TOOL script.CheckBody sootOutput)
      if [[ true != $tempInfo ]] {
        echo "exist Error when get active body"
        echo $tempInfo
        i=$((i-1))
        continue
      }

      # 将变异后的结果写入到 curMutant 中
      echo "Load $nextStep. Saved as curMutant."
      mv sootOutput curMutant
    }

    echo "------------------------------------------------------"

    if [[ ! -e curMutant ]] {
      mv lastMutant curMutant
    }

    # 运行新的程序得到 log
    echo "run  \"java -cp curMutant jnt.scimark2.commandline\"  to get coverage and log"
    timeout $TIMEOUT"s" java -cp curMutant jnt.scimark2.commandline >run.log 2>&1
    if (( $? == 124 )) {
      echo "Timeout! Remain $timeoutCount"
      timeoutCount=$((timeoutCount-1))
      continue
    }
    echo "\"java -cp curMutant jnt.scimark2.commandline\"  done"
    java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log

    tempInfo=(${(ps:\n:)"$(java -cp $TOOL script.ExceptionSceneCoverage curMutant _DTJVM.log run.log)"})
    curStructureNum=$tempInfo[1]
    curScenarioNum=$tempInfo[2]
    curStructures=$tempInfo[3]
    curScenarios=$tempInfo[4]
    echo "StructureNum: $lastStructureNum -> $curStructureNum"
    echo "ScenarioNum: $lastScenarioNum -> $curScenarioNum"
    echo "Structures:"
    echo "last: "$lastStructures
    echo "curr: "$curStructures
    echo "Scenarios:"
    echo "last: "$lastScenarios
    echo "curr: "$curScenarios

    if (( $#curStructureNum == 0 || $#curScenarioNum == 0 )) { # 获取覆盖率失败，重新 mutate
      echo "curStructureNum or curScenarioNum is zero"
      if [[ -f _DTJVM.log ]] {
        mv _DTJVM.log _DTJVM"Test"$curTestNum.log
        mv curMutant $ScimarkDir"Test"$curTestNum
        [[ -f run.log ]] && mv run.log runTest$curTestNum.log
        echo "Fail. Saved as $ScimarkDir"Test"$curTestNum in Epoch $epoch"
        curTestNum=$((curTestNum + 1))
      }
      continue
    }

    # throw 和 catch 的覆盖率
    java -cp $TOOL script.ThrowCatchCoverage curMutant _DTJVM.log

    leaf=$(countLeaf $ScimarkDir $curStructureNum)
    mv _DTJVM.log _DTJVM$curStructureNum.$leaf.log
    mv curMutant $ScimarkDir$curStructureNum.$leaf
    [[ -f error.txt ]] && mv error.txt error$curStructureNum.$leaf.txt
    [[ -f run.log ]] && mv run.log run$curStructureNum.$leaf.log
    echo "Finish combinators. Saved as $ScimarkDir$curStructureNum.$leaf in Epoch $epoch"

    curSeedNum=$((curSeedNum+1))
    echo '-------------------------------------------------------------------------------'
  }

  cd .. # cd $epoch
}

cd .. # exit strategy"4"

echo "Finish mutate3.sh"