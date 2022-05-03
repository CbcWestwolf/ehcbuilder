This repository contains scripts and jar for running EHCBuilder and EHCRandom.

# Files Tree

```
├── README.md
├── fuzzer
│   ├── dacapo
│   │		├── dacapo0/
│   │		├── dacapo0_unins/
│   │		├── jar/
│   │		├── ehcbuilder-jar-with-dependencies.jar
│   │		├── _DTJVMavrora.log
│   │		├── _DTJVMbatik.log
│   │		├── _DTJVMfop.log
│   │		├── _DTJVMh2.log
│   │		├── _DTJVMxalan.log
│   │		├── config.sh
│   │		├── ehcrandom.sh
│   │		├── ehcbuilder.sh
│   │		├── ehcbuilder_opt.sh
│   │		└── id-class-method.txt
│   └── scimark2
│   		├── scimark0/
│   		├── scimark_unins/
│   		├── ehcbuilder-jar-with-dependencies.jar
│   		├── _DTJVM0.log
│   		├── config.sh
│   		├── ehcrandom.sh
│   		├── ehcbuilder.sh
│   		├── ehcbuilder_opt.sh
│   		└── id-class-method.txt
└── experiments
    ├── dacapo
    │		├── config.sh
    │		├── ehcbuilder-jar-with-dependencies.jar
    │		├── getJVMCov.sh
    │		├── getThrowCatchCoverage.sh
    │		└── runOnJVMs.sh
    └── scimark2
    		├── config.sh
    		├── ehcbuilder-jar-with-dependencies.jar
    		├── getJVMCov.sh
    		├── getThrowCatchCoverage.sh
    		└── runOnJVMs.sh
```

* fuzzer: contains all fuzzer ( EHCRandom, EHCBuilder, EHCBuilder with optimization). 
  * dacapo: contains all the scripts and execution trace for running EHCBuilder on Dacapo
  * scimark2: contains all the scripts and execution trace for running EHCBuilder on Scimark2.0
* experiments: contains all scripts for experiments in Paper

# Requirement

* `zsh` is needed for running the scripts.

* For specifying the benchmark of dacapo, you need to specify the benchmark in `DacapoArg` in `config.sh`.  Five benchmarks`avrora batik h2 fop xalan` are available.
* For differential testing, you need to specify JVMs location in `jvmPaths` arrays in `config.sh` in `experiments`.
* For collecting JVM coverage using *gcov*, you need to specify HotSpot location in `projectDir` in `getJVMCov.sh` in `experiments`

# How to run fuzzer on dacapo

Assume that you want to run `fop`, and now the path is `./fuzzer/dacapo/`:

```zsh
./ehcrandom.sh  2>&1 | tee -a ehcrandom.log  # run EHCRandom
./ehcbuilder.sh 2>&1 | tee -a ehcbuilder.log # run EHCBuilder
./ehcbuilder_opt.sh 2>&1 | tee -a ehcbuilder_opt.log # run EHCBuilder with Mutators Combination
```

Then you would get three mutants directory `fop0`, `fop2` and `fop4`, and three mutation log `ehcrandom.log`, `ehcbuilder.log` and `ehcbuilder_opt.log`

# How to do experiment in paper

## Differential Testing

```bash
./runOnJVMs.sh fop0 fop2 fop4
```

Then you would get three directory `fop0_result`, `fop2_result` and `fop4_result`. Each `fop*_result` directory may contains `cmp_***.log` if mutants trigger differences:

* cmp_args.log: differences in `-Xmixed` `-XInt` and `-XComp` in HotSpot
* cmp_jvms.log: differences in HotSpot, OpenJ9, Zulu and GraalVM **with** verification

* cmp_noverify.log: differences in HotSpot, OpenJ9, Zulu and GraalVM **without** verification

## Table 3

To get data in Table 3, one or more mutation logs are needed. For example,

```bash
java -cp ehcbuilder-jar-with-dependencies.jar script.CountNodes2 ehcrandom.log ehcbuilder.log ehcbuilder_opt.log
```

will collect all nodes generated last step.

## Table 4

To get data in Table 4, one or more mutation logs are needed. For example,

```bash
java -cp ehcbuilder-jar-with-dependencies.jar script.CountScenarios ehcrandom.log ehcbuilder.log ehcbuilder_opt.log
```

will collect all chains generated last step.

## Table 5

To get coverage in Table 5, one mutator directory is needed. For example,

```bash
./getJVMCovs.sh fop0
```

will collect JVM code coverage covered by EHCRandom

## Table 6

To get data in Table 6, one or more mutator directories are needed. For example, 

```bash 
./getThrowCatchCoverage.sh fop0 fop2 fop4
```

will collect throwing catching number and rate generated last step.

