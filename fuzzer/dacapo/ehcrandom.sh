#!/bin/zsh

# 随机地选择 mutator 进行变异
# 中间不通过 log 或者 coverage 来筛选，只通过 script.CheckBody 来筛选

# 0. 加载配置文件
# set -e
source config.sh

# 1. 检查是否已经完成插桩
# 检查 $BenchmarkDir"0" _DTJVM$BenchmarkArg.log 是否存在
for item ($BenchmarkDir"0" _DTJVM$BenchmarkArg.log) {
  if [[ ! -e $item ]] {
    echo $item' not exist'
    exit 1
  }
}

rm -rf $BenchmarkTrash >/dev/null 2>&1

# 2. 进行变异

# 创建 $BenchmarkArg"0" 目录
if [[ -d $BenchmarkArg"0" ]] {
  rm -rf $BenchmarkArg"0" >/dev/null 2>&1
}
mkdir $BenchmarkArg"0"

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

cd $BenchmarkArg"0"
# 每个 benchmark 要生成 EPOCH_NUM 条链
for ((epoch = 1; epoch <= $EPOCH_NUM; ++epoch)) {
  # 一条链跑完, 直接跑下条链
  [[ -d $epoch ]] && continue

  mkdir $epoch
  cd $epoch

  echo -e '\n========================= Chain '$epoch' =========================' # -e 表示启用转义功能

  if [[ ! -e $BenchmarkDir"0" || ! -e _DTJVM0.log ]] {
    echo "Copy $BenchmarkRoot/$BenchmarkDir0 and _DTJVM$BenchmarkArg.log to current dir"
    rm -rf $BenchmarkDir"0" >/dev/null 2>&1
    cp -r $BenchmarkRoot/$BenchmarkDir"0" $BenchmarkDir"0"
    cp "$BenchmarkRoot/_DTJVM$BenchmarkArg.log" _DTJVM0.log
  }

  # 一条 Chain 由 $BenchmarkDir$depth 组成
  # $depth 从 1 开始到 $CHAIN_LENGTH
  # 每一轮 mutation 都基于 _DTJVM(i-1).log 和 dacapo(i-1)

  curSeedNum=0                       # 作为 mutation 的种子
  curTestNum=1                       # 不作为 mutation 的种子, 但可以进行 diff testing
  timeoutCount=1000                  # 统计超时的次数，用于防止无限循环
  testThreshold=300                  # 用于 diiferential testing 的数量

  while (( $((curSeedNum + curTestNum)) < $testThreshold && $timeoutCount > 0 )) {
    rm -rf sootOutput _DTJVM.log error.txt run.log $BenchmarkTrash >/dev/null 2>&1

    echo "-------------- epoch: $epoch,  seedNum: $curSeedNum,  testNum: $curTestNum --------------"

    randNum=$(generateRandomNum $mutatorNum)
    mutator=$mutators[$((randNum+1))]
    echo $mutator

    if [[ $mutator == "InsertExcepion" ]] { 

      randNum=$(generateRandomNum $insertExceptionMutatorsNum)
      mutator=$insertExceptionMutators[$((randNum+1))]
      echo $mutator
      
      # testThrow 并获取信息
      startTimeCount
      echo -e "
      testThrow: {
        Args: {
          lastIndex:        $curSeedNum
          prefix:           $BenchmarkDir,
          app:              Harness,
          args:             \"$BenchmarkArg\",
          rethrow:          false
        }"
      tempInfo=$(testThrow $curSeedNum $BenchmarkDir Harness "$BenchmarkArg" "false")
      retVal=$? # 每一条语句都有一个返回值, 所以一定要在这里先保存返回值
      if (( $retVal == 1 )) {
        echo "Function testThrow wrong arguments"
        endTimeCount InsertException
        exit 1
      } elif (( $retVal == 2 )) {
        echo "Used up times and not found exception in error.txt"
        endTimeCount InsertException
        continue
      } 
      array=(${=tempInfo})
      if (( $#array != 4 )) {
        echo "testThrow return wrong: "$tempInfo
        endTimeCount InsertException
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
          prefix:           $BenchmarkDir,
          useCounter:       true,
          mutator:         $mutator
        }"
      ThrowCatchInfo=$(
        insertThrowCatch $curSeedNum $throwClassName \
          $throwMethodName $throwMethodID $throwStmtID $BenchmarkDir "true" $mutator
      )
      retVal=$?
      if (( $retVal == 1 )) {
        echo "error.txt shows that only one method in call stack"
        endTimeCount InsertException
        break
      } elif (( $retVal == 2 )) {
        echo "ParseWrap shows no NewException"
        endTimeCount InsertException
        continue
      } elif (( $retVal != 0 )) {
        echo "ThrowAndCatch run error"
        echo "tempInfo in testThrow $ThrowCatchInfo"
        endTimeCount InsertException
        continue
      }
      array=(${=ThrowCatchInfo})
      if (( $#array != 8 )) {
        echo "insertThrowCatch return wrong: "$ThrowCatchInfo
        endTimeCount InsertException
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
      endTimeCount InsertException

      # 将 mutate 得到的 class 文件移动到原目录中
      rm -rf temp >/dev/null 2>&1
      mv sootOutput temp
      cp -r $BenchmarkDir$curSeedNum sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $BenchmarkDir$curSeedNum 不需要加 /*
      rsync -a temp/ sootOutput
      rm -rf temp >/dev/null 2>&1

    } elif [[ $mutator == "RethrowException" ]] {

      startTimeCount

      # testThrow 并获取信息
      echo -e "
      testThrow: {
        Args: {
          lastIndex:        $curSeedNum
          prefix:           $BenchmarkDir,
          app:              Harness,
          args:             \"$BenchmarkArg\",
          rethrow:          true
        }"
      tempInfo=$(testThrow $curSeedNum $BenchmarkDir Harness "$BenchmarkArg" "true")
      retVal=$? # 每一条语句都有一个返回值, 所以一定要在这里先保存返回值
      if (( $retVal == 1 )) {
        echo "Function testThrow wrong arguments"
        endTimeCount RethrowException
        exit 1
      } elif (( $retVal == 2 )) {
        echo "Used up times and not found exception in error.txt"
        endTimeCount RethrowException
        continue
      } 
      array=(${=tempInfo})
      if (( $#array != 4 )) {
        echo "testThrow return wrong: "$tempInfo
        endTimeCount RethrowException
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
          prefix:           $BenchmarkDir,
          useCounter:       false
        }"
      ThrowCatchInfo=$(
        insertThrowCatch $curSeedNum $throwClassName \
          $throwMethodName $throwMethodID $throwStmtID $BenchmarkDir "false"
      )
      retVal=$?
      if (( $retVal == 1 )) {
        echo "error.txt shows that only one method in call stack"
        endTimeCount RethrowException
        break
      } elif (( $retVal == 2 )) {
        echo "ParseWrap shows no NewException"
        endTimeCount RethrowException
        continue
      } elif (( $retVal != 0 )) {
        echo "ThrowAndCatch run error"
        echo "tempInfo in testThrow $ThrowCatchInfo"
        endTimeCount RethrowException
        continue
      }
      array=(${=ThrowCatchInfo})
      if (( $#array != 8 )) {
        echo "insertThrowCatch return wrong: "$ThrowCatchInfo
        endTimeCount RethrowException
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
      endTimeCount RethrowException

      # 将 mutate 得到的 class 文件移动到原目录中
      rm -rf temp >/dev/null 2>&1
      mv sootOutput temp
      cp -r $BenchmarkDir$curSeedNum sootOutput # 注意这里在复制前 sootOutput 不存在, 所以 $BenchmarkDir$curSeedNum 不需要加 /*
      rsync -a temp/ sootOutput
      rm -rf temp >/dev/null 2>&1

    } elif [[ $mutator == "AddCauseAndSuppressed" ]] {
      cp -r $BenchmarkDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中

      startTimeCount
      tempInfo=$(java -cp $TOOL mutation.AddCauseOrSuppressed $BenchmarkDir$curSeedNum $curSeedNum)
      endTimeCount AddCauseAndSuppressed
      echo $tempInfo

      if [[ $tempInfo == Error* ]] {
        continue
      }
    
    } elif [[ $mutator == "InsertGoto" ]] {

      cp -r $BenchmarkDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中
      startTimeCount
      tempInfo=$(java -cp $TOOL mutation.InsertGoto $BenchmarkDir$curSeedNum $curSeedNum "true")
      endTimeCount InsertGoto
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

      cp -r $BenchmarkDir$curSeedNum sootOutput # 结果先暂存在 sootOutput 中
      startTimeCount
      modifyInfo=$(java -cp $TOOL mutation.ModifyException $BenchmarkDir$curSeedNum $curSeedNum)
      endTimeCount ModifyException
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
    startTimeCount
    echo "run  \"java -cp sootOutput:$BenchmarkLib Harness $BenchmarkArg\"  to get coverage and log"
    timeout -s KILL $TIMEOUT"s" java -cp sootOutput:$BenchmarkLib Harness "$BenchmarkArg" >run.log 2>&1
    if (( $? == 137 )) {
      endTimeCount RunMutant
      echo "Timeout! Remain $timeoutCount"
      timeoutCount=$((timeoutCount-1))
      continue
    }
    endTimeCount RunMutant

    # 转换 log，获取异常信息
		startTimeCount
    java -cp $TOOL script.LogFormatter _DTJVM.log _DTJVM.log
    endTimeCount LogFormatter

    startTimeCount
    tempInfo=(${(ps:\n:)"$(java -cp $TOOL script.ExceptionSceneCoverage sootOutput _DTJVM.log run.log)"})
    endTimeCount ExceptionSceneCoverage
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
        mv sootOutput $BenchmarkDir"Test"$curTestNum
        [[ -f run.log ]] && mv run.log runTest$curTestNum.log
        echo "Fail to $nextStep. Saved as $BenchmarkDir"Test"$curTestNum in Epoch $epoch"
        curTestNum=$((curTestNum + 1))
      }
      continue
    }

    # throw 和 catch 的覆盖率
    startTimeCount
    java -cp $TOOL script.ThrowCatchCoverage sootOutput _DTJVM.log
    endTimeCount ThrowCatchCoverage

    curSeedNum=$((curSeedNum + 1))

    mv _DTJVM.log _DTJVM$curSeedNum.log
    mv sootOutput $BenchmarkDir$curSeedNum
    [[ -f error.txt ]] && mv error.txt error$curSeedNum.txt
    [[ -f run.log ]] && mv run.log run$curSeedNum.log
    echo "Finish $mutator. Saved as $BenchmarkDir$curSeedNum in Epoch $epoch"

    echo '-------------------------------------------------------------------------------'
  }

  cd .. # exit $epoch

}  # while

cd .. # exit $BenchmarkArg"0"

printTimeCount # print time count for each item

echo "Finish mutate0.sh."