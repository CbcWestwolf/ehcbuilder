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

    for dir ($(ls -d dacapo*)) {
      if [[ $dir == dacapoTest* ]] {
        continue
      }

      cur=$dir[7,-1] # 截取 dacapo 之后的字符串
      if [[ -d dacapo$cur && -f _DTJVM$cur.log ]] {
        echo dacapo$cur
        java -cp $TOOL script.ThrowCatchCoverage dacapo$cur _DTJVM$cur.log
      }
    }

    cd .. # cd $num
  }

  cd .. # cd $mutantsDir


}