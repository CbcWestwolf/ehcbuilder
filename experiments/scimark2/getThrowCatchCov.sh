#!/bin/zsh

source config.sh

for mutantsDir ($*) {

  cd $mutantsDir
  echo "========================== $mutantsDir =========================="
  for num ($(ls .)) {
    [ ! -d $num ] && continue # 跳过非目录的文件
    [[ $num == lcov_* ]] && continue
    echo "-------------------------------------------- $num --------------------------------------------"
    cd $num

    for dir ($(ls -d scimark*)) {
      if [[ $dir == scimarkTest* ]] {
        continue
      }

      cur=$dir[8,-1] # 截取 scimark 之后的字符串
      if [[ -d scimark$cur && -f _DTJVM$cur.log ]] {
        echo scimark$cur
        java -cp $TOOL script.ThrowCatchCoverage scimark$cur _DTJVM$cur.log
      }
    }

    cd .. # cd $num
  }

  cd .. # cd $mutantsDir


}