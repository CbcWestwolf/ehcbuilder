#!/bin/zsh

# 随机地选择 mutator 进行变异
# 中间不通过 log 或者 coverage 来筛选，只通过 script.CheckBody 来筛选

# 0. 加载配置文件
# set -e
source config.sh

# 1. 检查是否已经完成插桩
# 检查 $DacapoDir"0" _DTJVM$DacapoArg.log id-class-method.txt 是否存在
for item ($DacapoDir"0" _DTJVM$DacapoArg.log id-class-method.txt $DacapoDir"_unins") {
  if [[ ! -e $item ]] {
    echo $item' not exist'
    exit 1
  }
}

rm -rf scratch >/dev/null 2>&1

# 2. 进行变异

# 创建 $DacapoArg"0" 目录
if [[ -d $DacapoArg"0" ]] {
  rm -rf $DacapoArg"0" >/dev/null 2>&1
}
mkdir $DacapoArg"0"

mutators=(
  InsertExcepion RethrowException AddCauseAndSuppressed InsertGoto ModifyException
)

mutatorNum=$#mutators

insertExceptionMutators=(
  ExErrorOnSpot   ExRuntimeOnSpot   ExExceptionOnSpot
  ExErrorOnCaller ExRuntimeOnCaller ExExceptionOnCaller
  ImErrorOnSpot   ImRuntimeOnSpot   ImExceptionOnSpot
  ImErrorOnCaller ImRuntimeOnCaller ImExceptionOnCaller
)

insertExceptionMutatorsNum=$#insertExceptionMutators

cd $DacapoArg"0"
# 每个 benchmark 要生成 EPOCH_NUM 条链
for ((epoch = 1; epoch <= $EPOCH_NUM; ++epoch)) {
  # 一条链跑完, 直接跑下条链
  [[ -d $epoch ]] && continue

  mkdir $epoch
  cd $epoch

  echo -e '\n========================= Chain '$epoch' =========================' # -e 表示启用转义功能

  if [[ ! -e $DacapoDir"0" || ! -e _DTJVM0.log ]] {
    echo "Copy $DacapoRoot/$DacapoDir0 and _DTJVM$DacapoArg.log to current dir"
    rm -rf $DacapoDir"0" >/dev/null 2>&1
    cp -r $DacapoRoot/$DacapoDir"0" $DacapoDir"0"
    cp "$DacapoRoot/_DTJVM$DacapoArg.log" _DTJVM0.log
  }

  # 一条 Chain 由 $DacapoDir$depth 组成
  # $depth 从 1 开始到 $CHAIN_LENGTH
  # 每一轮 mutation 都基于 _DTJVM(i-1).log 和 dacapo(i-1)

  curSeedNum=0                       # 作为 mutation 的种子
  curTestNum=1                       # 不作为 mutation 的种子, 但可以进行 diff testing
  timeoutCount=1000                  # 统计超时的次数，用于防止无限循环
  testThreshold=300                  # 用于 diiferential testing 的数量

  while (( $((curSeedNum + curTestNum)) < $testThreshold && $timeoutCount > 0 )) {
    rm -rf sootOutput _DTJVM.log error.txt run.log scratch >/dev/null 2>&1

    echo "-------------- epoch: $epoch,  seedNum: $curSeedNum,  testNum: $curTestNum --------------"

    randNum=$(generateRandomNum $mutatorNum)
    mutator=$mutators[$((randNum+1))]
    echo $mutator

    if [[ $mutator == "InsertExcepion" ]] { 

      randNum=$(generateRandomNum $insertExceptionMutatorsNum)
      mutator=$insertExceptionMutators[$((randNum+1))]
      echo $mutator
      
      # testThrow 并获取信息
      echo -e "
      testThrow: {
        Args: {
          lastIndex:        $curSeedNum
          prefix:           $DacapoDir,
          app:              Harness,
          args:             \"$DacapoArg\",
          rethrow:          false
        }"
      tempInfo=$(testThrow $curSeedNum $DacapoDir Harness "$DacapoArg" "false")
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
          lastIndex:        $curSeedNum
          throwClassName:   $throwClassName,
          throwMethodName:  $throwMethodName,
          throwMethodID:    $throwMethodID,
          throwStmtID:      $throwStmtID,
          prefix:           $DacapoDir,
          useCounter:       true,
          mutator:         $mutator
        }"
      ThrowCatchInfo=$(
        insertThrowCatch $curSeedNum $throwClassName \
          $throwMethodName $throwMethodID $throwStmtID $DacapoDir "true" $mutator
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
      cp -r $DacapoDir$curSeedNum sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $DacapoDir$curSeedNum 不需要加 /*
      rsync -a temp/ sootOutput
      rm -rf temp >/dev/null 2>&1

    } elif [[ $mutator == "RethrowException" ]] {

      # testThrow 并获取信息
      echo -e "
      testThrow: {
        Args: {
          lastIndex:        $curSeedNum
          prefix:           $DacapoDir,
          app:              Harness,
          args:             \"$DacapoArg\",
          rethrow:          true
        }"
      tempInfo=$(testThrow $curSeedNum $DacapoDir Harness "$DacapoArg" "true")
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
          lastIndex:        $curSeedNum
          throwClassName:   $throwClassName,
          throwMethodName:  $throwMethodName,
          throwMethodID:    $throwMethodID,
          throwStmtID:      $throwStmtID,
          prefix:           $DacapoDir,
          useCounter:       false
        }"
      ThrowCatchInfo=$(
        insertThrowCatch $curSeedNum $throwClassName \
          $throwMethodName $throwMethodID $throwStmtID $DacapoDir "false"
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
      cp -r $DacapoDir$curSeedNum sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $DacapoDir$curSeedNum 不需要加 /*
      rsync -a temp/ sootOutput
      rm -rf temp >/dev/null 2>&1

    } elif [[ $mutator == "AddCauseAndSuppressed" ]] {
      cp -r $DacapoDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中

      tempInfo=$(java -cp $TOOL mutation.AddCauseOrSuppressed $DacapoDir$curSeedNum $curSeedNum)
      echo $tempInfo

      if [[ $tempInfo == Error* ]] {
        continue
      }
    
    } elif [[ $mutator == "InsertGoto" ]] {

      cp -r $DacapoDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中
      tempInfo=$(java -cp $TOOL mutation.InsertGoto $DacapoDir$curSeedNum $curSeedNum "true")
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

    } elif [[ $mutator == "ModifyException" ]] {

      cp -r $DacapoDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中
      modifyInfo=$(java -cp $TOOL mutation.ModifyException $DacapoDir$curSeedNum $curSeedNum)
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
      echo 'Should not reach here! mutator: '$mutator
      exit 1
    }

    echo "Check Bodies in sootOutput"
    tempInfo=$(java -cp $TOOL script.CheckBody sootOutput)
    if [[ "true" != $tempInfo ]] {
      echo "exist Error when get active body"
      echo $tempInfo
      continue
    }

    # 运行新的程序得到 log
    echo "run  \"java -cp sootOutput:$DacapoLib Harness $DacapoArg\"  to get coverage and log"
    timeout $TIMEOUT"s" java -cp sootOutput:$DacapoLib Harness "$DacapoArg" >run.log 2>&1
    if (( $? == 124 )) {
      echo "Timeout! Remain $timeoutCount"
      timeoutCount=$((timeoutCount-1))
      continue
    }
    echo "\"java -cp sootOutput:$DacapoLib Harness $DacapoArg\"  done"
    java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log

    tempInfo=(${(ps:\n:)"$(java -cp $TOOL script.ExceptionSceneCoverage sootOutput _DTJVM.log run.log)"})
    curStructureNum=$tempInfo[1]
    curScenarioNum=$tempInfo[2]
    curStructures=$tempInfo[3]
    curScenarios=$tempInfo[4]
    echo "StructureNum: $curStructureNum"
    echo "ScenarioNum: $curScenarioNum"
    echo "Structures:" $curStructures
    echo "Scenarios:" $curScenarios

    if [[ $#curStructureNum == 0 || $#curScenarioNum == 0 || $curStructureNum -le 1 || $curScenarioNum -le 1 ]] { # 获取覆盖率失败，重新 mutate
      echo "curStructureNum or curScenarioNum is zero"
      if [[ -f _DTJVM.log ]] {
        mv _DTJVM.log _DTJVM"Test"$curTestNum.log
        mv sootOutput $DacapoDir"Test"$curTestNum
        [[ -f run.log ]] && mv run.log runTest$curTestNum.log
        echo "Fail to $nextStep. Saved as $DacapoDir"Test"$curTestNum in Epoch $epoch"
        curTestNum=$((curTestNum + 1))
      }
      continue
    }

    # throw 和 catch 的覆盖率
    java -cp $TOOL script.ThrowCatchCoverage sootOutput _DTJVM.log

    curSeedNum=$((curSeedNum + 1))

    mv _DTJVM.log _DTJVM$curSeedNum.log
    mv sootOutput $DacapoDir$curSeedNum
    [[ -f error.txt ]] && mv error.txt error$curSeedNum.txt
    [[ -f run.log ]] && mv run.log run$curSeedNum.log
    echo "Finish $mutator. Saved as $DacapoDir$curSeedNum in Epoch $epoch"

    echo '-------------------------------------------------------------------------------'
  }

  cd .. # exit $epoch

}  # while

cd .. # exit $DacapoArg"0"

echo "Finish mutate0.sh."