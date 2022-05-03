#!/bin/zsh

######################### 全局变量设置 #########################

# benchmark 项目路径
ScimarkRoot=$PWD

# 工具路径
TOOL=$ScimarkRoot'/ehcbuilder-jar-with-dependencies.jar'

# 超时时间(秒)
TIMEOUT=300

# 插桩过的 benchmark 目录
ScimarkDir='scimark'

# 注意! zsh 中下标起点是 1, bash 中下标起点是 0 !
# https://stackoverflow.com/questions/50427449/behavior-of-arrays-in-bash-scripting-and-zsh-shell-start-index-0-or-1/50433774

# jvms 名字列表
jvms=(
  HotSpot_OpenJDK11
  OpenJ9_OpenJDK11
  Zulu_OpenJDK11
  GraalVM_OpenJDK11
)
jvmNum=$#jvms

# jvm 路径列表
# download from https://adoptopenjdk.net/ and https://developer.ibm.com/javasdk/downloads/sdk8/
jvmPaths=(
  "<path-to-hotspot-java>"
  "<path-to-openj9-java>"
  "<path-to-zulu-java>"
  "<path-to-graalvm-java>"
)

hotspotArgs=(
  -Xint
  -Xcomp
  -noverify
)

CHAIN_LENGTH=10 # 链的长度
EPOCH_NUM=5    # 链的数量

# 进行 mutation 的类型
mutatorNum=5 # mutators 的个数（InsertGoto + ModifyException 两种，不包括 InsertGoto）

# 异常种类

errors=(
  java.lang.AssertionError  java.lang.InternalError  java.lang.Error  java.lang.ThreadDeath
  java.lang.OutOfMemoryError  java.lang.IllegalAccessError  java.lang.LinkageError  java.util.ServiceConfigurationError
  java.lang.VirtualMachineError  java.lang.ClassFormatError  java.lang.UnsatisfiedLinkError  java.lang.NoClassDefFoundError
  java.lang.annotation.AnnotationFormatError  java.io.IOError  java.lang.NoSuchMethodError  java.lang.IncompatibleClassChangeError
  java.lang.InstantiationError  java.lang.StackOverflowError  java.lang.ExceptionInInitializerError  java.lang.AbstractMethodError
  java.lang.NoSuchFieldError  java.nio.charset.CoderMalfunctionError  java.lang.reflect.GenericSignatureFormatError  java.lang.BootstrapMethodError  
  jdk.internal.util.jar.InvalidJarIndexError  sun.nio.ch.Reflect$ReflectionError  java.lang.VerifyError  java.lang.UnknownError  
  java.lang.ClassCircularityError
)

runtimeExceptions=(
  java.lang.IllegalStateException  java.lang.NullPointerException  java.lang.IllegalArgumentException
  java.lang.RuntimeException  java.lang.IllegalCallerException  java.lang.SecurityException
  java.lang.IndexOutOfBoundsException  java.lang.ClassCastException  java.lang.NegativeArraySizeException
  java.util.ConcurrentModificationException  java.lang.IllegalThreadStateException  java.lang.ArithmeticException
  java.lang.StringIndexOutOfBoundsException  java.nio.charset.IllegalCharsetNameException  java.nio.charset.UnsupportedCharsetException
  java.lang.UnsupportedOperationException  java.lang.NumberFormatException  java.security.AccessControlException
  java.io.UncheckedIOException  java.lang.LayerInstantiationException  java.util.MissingResourceException
  java.lang.ArrayIndexOutOfBoundsException  java.lang.reflect.UndeclaredThrowableException  java.util.NoSuchElementException
  java.util.MissingFormatArgumentException  java.util.UnknownFormatConversionException  java.util.FormatterClosedException
  java.util.IllformedLocaleException  java.util.regex.PatternSyntaxException  java.nio.file.InvalidPathException
  java.lang.reflect.MalformedParametersException  java.nio.BufferUnderflowException  java.lang.TypeNotPresentException
  java.lang.ArrayStoreException  java.lang.invoke.WrongMethodTypeException  java.lang.invoke.InvokerBytecodeGenerator$BytecodeGenerationException
  java.nio.file.FileSystemNotFoundException  java.nio.BufferOverflowException  java.nio.ReadOnlyBufferException
  java.lang.reflect.InaccessibleObjectException  java.nio.channels.NonWritableChannelException  java.nio.channels.NonReadableChannelException
  java.lang.module.FindException  java.lang.module.InvalidModuleDescriptorException  java.util.concurrent.RejectedExecutionException
  java.security.InvalidParameterException  java.util.IllegalFormatException  java.util.IllegalFormatPrecisionException
  java.time.DateTimeException  java.util.MissingFormatWidthException  java.util.FormatFlagsConversionMismatchException
  java.util.IllegalFormatWidthException  java.util.IllegalFormatFlagsException  java.util.IllegalFormatConversionException
  java.time.temporal.UnsupportedTemporalTypeException  java.util.IllegalFormatCodePointException  java.util.DuplicateFormatFlagsException
  java.util.UnknownFormatFlagsException  java.nio.file.ProviderNotFoundException  java.lang.module.ResolutionException
  java.security.ProviderException  java.lang.EnumConstantNotPresentException  java.lang.annotation.AnnotationTypeMismatchException
  java.lang.reflect.MalformedParameterizedTypeException  java.nio.channels.IllegalBlockingModeException  java.nio.channels.ClosedSelectorException
  java.nio.InvalidMarkException  java.nio.file.ProviderMismatchException  java.nio.file.FileSystemAlreadyExistsException
  java.util.concurrent.CancellationException  java.util.concurrent.CompletionException
  java.time.zone.ZoneRulesException  java.nio.channels.OverlappingFileLockException  java.nio.file.DirectoryIteratorException
  java.lang.annotation.IncompleteAnnotationException  java.util.InputMismatchException  java.nio.file.ClosedWatchServiceException
  java.nio.file.ClosedDirectoryStreamException  java.time.format.DateTimeParseException  java.nio.channels.CancelledKeyException
  java.nio.channels.NotYetBoundException  java.nio.channels.AlreadyBoundException  java.nio.channels.NotYetConnectedException
  java.nio.channels.UnsupportedAddressTypeException  java.nio.channels.UnresolvedAddressException  java.lang.IllegalMonitorStateException
  java.nio.channels.IllegalSelectorException  java.nio.channels.AlreadyConnectedException  java.nio.channels.ConnectionPendingException
  java.nio.channels.NoConnectionPendingException  java.nio.channels.ShutdownChannelGroupException  java.util.EmptyStackException
  java.nio.channels.IllegalChannelGroupException  java.nio.channels.AcceptPendingException  java.nio.channels.ReadPendingException
  java.nio.channels.WritePendingException
)

uncheckedExceptions=($errors $runtimeExceptions)

checkedExceptions=(
  java.io.IOException  java.lang.ClassNotFoundException  java.io.StreamCorruptedException
  java.lang.CloneNotSupportedException  java.lang.InterruptedException  java.lang.Exception
  java.io.UnsupportedEncodingException  java.io.NotActiveException  java.io.InvalidObjectException
  java.io.InvalidClassException  java.io.WriteAbortedException  java.io.OptionalDataException
  java.io.NotSerializableException  java.io.FileNotFoundException  java.io.InterruptedIOException
  java.io.ObjectStreamException  java.lang.InstantiationException  java.lang.IllegalAccessException
  java.lang.NoSuchFieldException  java.lang.NoSuchMethodException  java.lang.reflect.InvocationTargetException
  java.lang.ReflectiveOperationException  java.nio.charset.CharacterCodingException  java.net.MalformedURLException
  java.net.URISyntaxException  java.security.PrivilegedActionException  java.util.InvalidPropertiesFormatException
  java.io.SyncFailedException  java.io.EOFException  java.io.UTFDataFormatException
  java.security.NoSuchAlgorithmException  sun.util.locale.LocaleSyntaxException  java.nio.charset.MalformedInputException
  java.nio.charset.UnmappableCharacterException  java.nio.file.NoSuchFileException  java.security.cert.CertificateException
  java.security.cert.CertificateEncodingException  java.security.NoSuchProviderException  java.net.UnknownHostException
  java.net.UnknownServiceException  java.security.InvalidKeyException  java.security.InvalidAlgorithmParameterException
  javax.crypto.BadPaddingException  javax.crypto.IllegalBlockSizeException  java.security.SignatureException
  jdk.internal.org.xml.sax.SAXException  jdk.internal.org.xml.sax.SAXParseException  jdk.internal.util.xml.XMLStreamException
  java.nio.channels.AsynchronousCloseException  java.nio.channels.FileLockInterruptionException  java.nio.channels.ClosedByInterruptException
  java.nio.channels.ClosedChannelException  java.util.zip.ZipException  java.security.GeneralSecurityException
  java.security.DigestException  java.text.ParseException  java.nio.file.FileSystemException
  java.nio.file.FileAlreadyExistsException  java.security.KeyStoreException  sun.security.provider.PolicyParser$ParsingException
  java.security.cert.CertificateExpiredException  java.security.cert.CertificateNotYetValidException  java.security.cert.CertificateParsingException
  java.security.cert.CRLException  java.util.concurrent.ExecutionException  java.net.SocketException
  java.util.jar.JarException  java.security.KeyException  javax.crypto.NoSuchPaddingException
  javax.crypto.ShortBufferException  java.security.spec.InvalidParameterSpecException  javax.crypto.ExemptionMechanismException
  sun.nio.fs.UnixException  java.nio.file.NotLinkException  java.nio.file.NotDirectoryException
  java.nio.file.DirectoryNotEmptyException  java.util.concurrent.TimeoutException  java.util.zip.DataFormatException
  sun.security.util.PropertyExpander$ExpandException  java.nio.file.FileSystemLoopException  java.nio.file.AtomicMoveNotSupportedException
  java.security.UnrecoverableKeyException  java.security.UnrecoverableEntryException  java.net.SocketTimeoutException
  javax.security.auth.DestroyFailedException  java.nio.file.AccessDeniedException  java.nio.file.attribute.UserPrincipalNotFoundException
  sun.security.pkcs.ParsingException  jdk.internal.org.xml.sax.SAXNotRecognizedException  jdk.internal.org.xml.sax.SAXNotSupportedException
  java.net.ProtocolException  javax.security.auth.callback.UnsupportedCallbackException  java.security.spec.InvalidKeySpecException
  sun.net.www.ApplicationLaunchException  sun.net.ConnectionResetException  java.security.cert.CertPathValidatorException
  javax.crypto.CryptoPolicyParser$ParsingException  java.net.PortUnreachableException  sun.security.timestamp.TSResponse$TimestampException
  java.net.HttpRetryException  javax.net.ssl.SSLPeerUnverifiedException  javax.net.ssl.SSLException
  java.nio.channels.InterruptedByTimeoutException  java.lang.invoke.LambdaConversionException  java.lang.invoke.StringConcatException
)

exceptions=($uncheckedExceptions $checkedExceptions)
exceptionNUM=$#exceptions

######################### 函数声明 #########################

# param: num: 规定随机数的范围在 [0, num) 之间
# echo: 获取到的随机数
function generateRandomNum() {
  local num=$1
  local random=$(cat /dev/urandom | tr -dc '0-9' | head -c5)
  local result=$((random % $num))
  echo $result
}

# param: 无
# echo: 选中异常的字符串
function generateRandomException() {
  local chosenIndex=$(generateRandomNum $exceptionNUM)
  chosenIndex=$((chosenIndex + 1))
  echo ${exceptions[$chosenIndex]}
}

# param: 
#  1. 源 info 文件
#  2. 目标 info 文件
# echo:  选择收集覆盖率的所有文件
function filterInfo() {
  if (( $# != 2 )) {
    echo "参数错误：$*"
    return 1
  }  

  lcov -o $2 -e $1 '*/cpu/x86/c1_LinearScan_x86.*' \
    '*/cpu/x86/c1_LIRAssembler_x86.*' \
    '*/cpu/x86/c1_Runtime1_x86.*' \
    '*/cpu/x86/macroAssembler_x86.*' \
    '*/cpu/x86/sharedRuntime_x86_64.*' \
    '*/cpu/x86/stubGenerator_x86_64.*' \
    '*/cpu/x86/templateInterpreterGenerator_x86.*' \
    '*/cpu/x86/templateTable_x86.*' \
    '*/os/linux/os_linux.*' \
    '*/os_cpu/linux_x86/os_linux_x86.*' \
    '*/share/asm/assembler.*' \
    '*/share/asm/codeBuffer.*' \
    '*/share/c1/c1_Compilation.*' \
    '*/share/c1/c1_globals.*' \
    '*/share/c1/c1_GraphBuilder.*' \
    '*/share/c1/c1_Instruction.*' \
    '*/share/c1/c1_InstructionPrinter.*' \
    '*/share/c1/c1_IR.*' \ 
    '*/share/c1/c1_LinearScan.*' \
    '*/share/c1/c1_LIR.*' \
    '*/share/c1/c1_LIRAssembler.*' \
    '*/share/c1/c1_LIRGenerator.*' \
    '*/share/c1/c1_Optimizer.*' \
    '*/share/c1/c1_RangeCheckElimination.*' \
    '*/share/c1/c1_Runtime1.*' \
    '*/share/c1/c1_ValueMap.*' \
    '*/share/ci/bcEscapeAnalyzer.*' \
    '*/share/ci/ciExceptionHandler.*' \
    '*/share/ci/ciMethod.*' \
    '*/share/ci/ciMethodBlocks.*' \
    '*/share/ci/ciStreams.*' \
    '*/share/classfile/classFileParser.*' \
    '*/share/classfile/javaClasses.*' \
    '*/share/classfile/stackMapTable.*' \
    '*/share/classfile/verifier.*' \
    '*/share/code/codeCache.*' \
    '*/share/code/exceptionHandlerTable.*' \
    '*/share/code/nmethod.*' \
    '*/share/compiler/methodLiveness.*' \
    '*/share/interpreter/bytecodeInterpreter.*' \
    '*/share/interpreter/interpreterRuntime.*' \
    '*/share/interpreter/templateInterpreterGenerator.*' \
    '*/share/jvmci/jvmciRuntime.*' \
    '*/share/memory/universe.*' \
    '*/share/oops/constantPool.*' \
    '*/share/oops/generateOopMap.*' \
    '*/share/oops/method.*' \
    '*/share/opto/callnode.*' \
    '*/share/opto/cfgnode.*' \
    '*/share/opto/compile.*' \
    '*/share/opto/doCall.cpp' \
    '*/share/opto/graphKit.*' \
    '*/share/opto/machnode.*' \
    '*/share/opto/output.*' \
    '*/share/opto/parse.hpp' \
    '*/share/opto/runtime.*' \
    '*/share/prims/jniFastGetField.*' \
    '*/share/prims/jvmtiExport.*' \
    '*/share/runtime/deoptimization.*' \
    '*/share/runtime/frame.*' \
    '*/share/runtime/globals.*' \
    '*/share/runtime/interfaceSupport.*' \
    '*/share/runtime/javaCalls.*' \
    '*/share/runtime/os.*' \
    '*/share/runtime/safepoint.*' \
    '*/share/runtime/sharedRuntime.*' \
    '*/share/runtime/thread.*' \
    '*/share/utilities/exceptions.*' \
    '*/share/utilities/preserveException.*' \
    '*/share/utilities/vmError.*' >/dev/null 2>&1
}

# param: 要用 java 执行的命令，即 java ...
# echo: lineCov 和 funcCov （浮点数的形式）
function javaBaseline() {
  local projectDir='/home/lwb/jvms/baseline/hotspot_openjdk-11+28/'
  local srcDir="$projectDir"'src/'
  local javaApp="$projectDir"'build/linux-x86_64-normal-server-release/images/jdk/bin/java'

  # a) Resetting counters, remove all .gcda files
  lcov -z -d "$projectDir" >/dev/null 2>&1

  # b) create baseline coverage data file
  lcov -c -i -d "$projectDir" -b "$srcDir" -o base.info --ignore-errors graph >/dev/null 2>&1

  # run app in the jdk
  $javaApp $@ >/dev/null 2>&1

  # c) Capturing the current coverage state to a file
  # 不加 --ignore-errors graph 的话，会因为缺少 gcno 文件而无法执行
  lcov -c -d "$projectDir" -b "$srcDir" -o test.info --ignore-errors graph >/dev/null 2>&1

  # d) combine baseline and test coverage data
  local covInfo=$(lcov -a base.info -a test.info -o coverage.info) >/dev/null 2>&1

  # 用这条命令过滤出需要的文件夹：
  local covInfo=$(filterInfo coverage.info coverage.filter.info)
  # local covInfo=$(lcov -e coverage.info '*/hotspot/share/runtime/*' \
  #   '*/hotspot/share/ci/*' \
  #   '*/hotspot/share/opto/*' \
  #   '*/hotspot/share/interpreter/*' \
  #   '*/hotspot/share/code/*' \
  #   '*/hotspot/share/classfile/*' \
  #   '*/hotspot/share/oops/*' \
  #   '*/hotspot/share/utilities/*' \
  #   '*/hotspot/share/c1/*' \
  #   -o coverage.filter.info)
  
  # 获取这一行输出的覆盖率并通过 echo 返回
  local lineCov=$(echo $covInfo | grep lines)
  local funcCov=$(echo $covInfo | grep functions)
  lineCov=${lineCov%\%*} # 去除 % 及其右边的字符
  lineCov=${lineCov#*\:} # 去除 : 及其左边的字符
  funcCov=${funcCov%\%*}
  funcCov=${funcCov#*\:}
  echo $lineCov $funcCov

  # # e) Getting HTML output
  # genhtml coverage.filter.info --output-directory lcov_report --ignore-errors source >/dev/null 2>&1

  # remove .info
  rm base.info test.info coverage.info coverage.filter.info >/dev/null 2>&1
}

# param: 要用 java 执行的命令，即 java ...
# echo: lineCov 和 funcCov （浮点数的形式）
function javaBaselineNew() {
  local projectDir='/home/lwb/jvms/baseline/hotspot_openjdk-11+28/'
  local srcDir="$projectDir"'src/'
  local javaApp="$projectDir"'build/linux-x86_64-normal-server-release/images/jdk/bin/java'

  # a) Resetting counters, remove all .gcda files
  lcov -z -d "$projectDir" >/dev/null 2>&1
  rm -rf lcov_report test.info >/dev/null 2>&1

  # run app in the jdk
  $javaApp $@ >/dev/null 2>&1

  # b) Capturing the current coverage state to a file
  # 不加 --ignore-errors graph 的话，会因为缺少 gcno 文件而无法执行
  lcov -c -d "$projectDir" -b "$srcDir" -o test.info --ignore-errors graph >/dev/null 2>&1

  # 用这条命令过滤出需要的文件夹：
  local covInfo=$(lcov -e test.info '*/hotspot/share/runtime/*' \
    '*/hotspot/share/ci/*' \
    '*/hotspot/share/opto/*' \
    '*/hotspot/share/interpreter/*' \
    '*/hotspot/share/code/*' \
    '*/hotspot/share/classfile/*' \
    '*/hotspot/share/oops/*' \
    '*/hotspot/share/utilities/*' \
    '*/hotspot/share/c1/*' \
    -o test.filter.info) >/dev/null 2>&1

  # d) combine baseline and test coverage data
  local covInfo=$(genhtml test.info -o lcov_report --ignore-errors source 2>/dev/null)
  rm -rf lcov_report *.info >/dev/null 2>&1

  # 获取这一行输出的覆盖率并通过 echo 返回
  local lineCov=$(echo $covInfo | grep lines)
  local funcCov=$(echo $covInfo | grep functions)
  lineCov=${lineCov%\%*} # 去除 % 及其右边的字符
  lineCov=${lineCov#*\:} # 去除 : 及其左边的字符
  funcCov=${funcCov%\%*}
  funcCov=${funcCov#*\:}
  echo $lineCov $funcCov
}

# param:
#   1. lastIndex
#   2. prefix
#   3. 运行的主类，即 java -cp temp...
#   4. 是否调用 rethrow，是为 true，否为 false
# echo: index throwMethodID throwClassName throwMethodName throwStmtID
# return:
#   0: 正确执行
#   1: 参数不正确
#   2: 用光了 $InnerLoopTime 次也没有在 error.txt 中发现 exception
# 调用前必须不能有 error.txt 或者 sootOutput
# 返回 0 时一定有 error.txt, 返回 1 或者 2 时一定没有 error.txt
# 过程中产生的 temp 或者 sootOutput 会在调用后删除
function testThrow() {
  if (( $# != 4 )) {
    echo "参数错误：$*"
    return 1
  }
  
  local lastIndex=$1
  local prefix=$2
  local app=$3
  local rethrow=$4
  local OuterLoopTime=30

  if [[ -e error.txt || -e sootOutput ]] {
    echo "Should not exist error.txt or sootOutput"
    exit 1
  }
  
  # 如果 error.txt 不存在，或者在 error.txt 中找不到 'NewException'
  while [[ ! -e ./error.txt ||
      $(grep -c "java.lang.NullPointerException" ./error.txt) -eq '0' ]] {

    if (( $OuterLoopTime > 0 )) {
      OuterLoopTime=$((OuterLoopTime - 1))
    } else {
      rm error.txt >/dev/null 2>&1
      rm -rf temp sootOutput >/dev/null 2>&1
      return 2
    }        

    local InnerLoopTime=30 # 这个地方可能会死循环，尝试 30 次 TestThrow 就停止

    # 根据 log 加入 throw
    if [[ -d 'temp' ]] {
      rm -rf 'temp' >/dev/null 2>&1
    }
    cp -r $prefix$lastIndex 'temp'
    while [[ ! -d "sootOutput" ]] {
      # 超过 30 次就停止
      if (( $InnerLoopTime > 0 )) {
        InnerLoopTime=$((InnerLoopTime - 1))
      } else {
        rm error.txt >/dev/null 2>&1
        rm -rf temp sootOutput >/dev/null 2>&1
        return 2
      }
      # TestThrow 不应该出现死循环！如果出现了死循环，一定是 TestThrow 的实现有问题
      if [[ $rethrow == 'false' ]] {
        local testInfo=$(java -cp $TOOL mutation.TestThrow $prefix$lastIndex _DTJVM$lastIndex.log)
      } elif [[ $rethrow == 'true' ]] {
        local testInfo=$(java -cp $TOOL mutation.TestRethrow $prefix$lastIndex _DTJVM$lastIndex.log)
      } else {
        echo "参数错误：$rethrow"
        return 1
      }
    }
    rsync -a sootOutput/ 'temp'
    rm -rf sootOutput >/dev/null 2>&1

    array=(${=testInfo})
    if (( $#array != 4 )) {
      continue
    }
    local throwMethodID=$array[1]   # 加入 'throw' 的 methodID
    local throwClassName=$array[2]  # 加入 'throw' 的类名
    local throwMethodName=$array[3] # 加入 'throw' 的函数名
    local throwStmtID=$array[4]     # 加入 'throw' 的 StmtID

    # 运行加入 throw 的 scimark 得到新的 _DTJVM.log 和 error.txt
    timeout $TIMEOUT"s" java -cp temp $app 2>error.txt
    if [[ $? == 124 ]] {
      rm error.txt >/dev/null 2>&1
    }
    rm _DTJVM.log >/dev/null 2>&1
  }

  rm -rf temp sootOutput scratch >/dev/null 2>&1
  
  echo "$throwMethodID $throwClassName $throwMethodName $throwStmtID"
  return 0
}

# param:
#   1. lastIndex
#   2. throwClassName
#   3. throwMethodName
#   4. throwMethodID
#   5. throwStmtID
#   6. prefix
#   7. use counter
#   (8. nextStep)
# echo: catchClassName catchMethodName wrapClassName wrapMethodName wrapStmtIDs exceptionName
# return:
#   0: 正确执行
#   1: error.txt 显示调用栈上只有 throw 语句所在的方法了
#   2: "no NewException"
#   3: ThrowAndCatch 执行错误
# 调用前必须有 error.txt, 一定不能有 sootOutput
# 返回 0 时一定产生了 sootOutput
function insertThrowCatch() {
  if (( $# > 8 || $# < 7 )) {
    echo "参数错误：$*"
    return 1
  }

  local lastIndex=$1
  local throwClassName=$2
  local throwMethodName=$3
  local throwMethodID=$4
  local throwStmtID=$5
  local prefix=$6
  local useCounter=$7
  local nextStep=$8 # 引入 nextStep
  local COUNT=30 # 尝试 30 次
  local tempInfo=""

  if [[ -e sootOutput ]] {
    # 进入 insertThrowCatch 的时候存在 sootOutput
    exit 1
  }

  if [[ ! -e error.txt ]] {
    # '进入 insertThrowCatch 的时候没有 error.txt
    exit 1
  }

  while [[ ! -d "sootOutput" && $COUNT -gt '0' ]] { # 当 ThrowAndCatch 没有得到结果时；并且尝试次数少于 100

    COUNT=$((COUNT - 1))

    if (( $# == 8 )) {
      tempInfo=$(java -cp $TOOL mutation.ThrowAndCatch $prefix$lastIndex $throwMethodID $throwStmtID $lastIndex $useCounter \
        "error.txt" $throwClassName $throwMethodName $nextStep)
    } else {
      tempInfo=$(java -cp $TOOL mutation.ThrowAndCatch $prefix$lastIndex $throwMethodID $throwStmtID $lastIndex $useCounter \
        "error.txt" $throwClassName $throwMethodName)
    }
    
    if [[ $? != 0 || $tempInfo == Error* || $#tempInfo == 0 ]] {
      rm -rf sootOutput >/dev/null 2>&1
      continue
    }

    break
  }
  if (( $COUNT == 0 )) {
    rm -rf sootOutput >/dev/null 2>&1
    return 2
  } else {
    if [[ ! -e sootOutput ]] { # 这里不应该没有 sootOutput
      exit 1
    }
    echo $tempInfo
    return 0
  }
}

# param: prefix
# echo: currentSeedNum
# 统计以 $prefix$currentSeedNum 的形式的最大值
function countSeed() { 
  local prefix=$1
  local result=0
  while [[ -d $prefix$result ]] {
    result=$((result + 1))
  }
  echo $((result - 1))
}

# param: prefix
# echo: currentExceptionNum
# 统计以 $prefix$currentExceptionNum".0" 的形式的最大值
function countExceptionWithLeaf0() {
  local prefix=$1
  local result=0
  while [[ -d $prefix$result".0" ]] {
    result=$((result + 1))
  }
  echo $((result - 1))
}

# param: prefix depth
# echo: currentLeafum
# 统计以 $prefix$depth"."$leaf 的形式的 $leaf 的下一个值
function countLeaf() {
  local prefix=$1
  local depth=$2
  local leaf=0
  while [[ -d $prefix$depth"."$leaf ]] {
    leaf=$((leaf + 1))
  }
  echo $leaf
}

# param: prefix
# echo: nextTestNum
# 统计以 $prefix$xx 的形式的下一个值
function countTestDir() { 
  local prefix=$1
  local nextTestNum=0
  while [[ -d $prefix$((nextTestNum)) ]] {
    nextTestNum=$((nextTestNum + 1))
  }
  echo $nextTestNum
}
