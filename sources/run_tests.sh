#!/bin/bash

if [	-z "$HOSTRTL"	]; then
	echo "HOSTRTL is not set"
	exit 1
fi
if [	-z "$TARGETRTL"	]; then
	echo "TARGETRTL is not set"
	exit 1
fi
if [	-z "$LLVMBIN"	]; then
	echo "LLVMBIN is not set"
	exit 1
fi

set -uo pipefail

CC=$LLVMBIN/clang
CXX=$LLVMBIN/clang++

# Set commands here

CXXFLAGS="-I$TARGETRTL -target x86_64-pc-linux-gnu -fopenmp -fopenmp-targets=amdgcn-fiji-amdhsa"
LXXFLAGS="-L$HOSTRTL -L$TARGETRTL" 

# Format must have "@@" preceding the key and ':' to separate the value
# @@key: value
#
# getValue $key $file
getValue()
{
  key=$1
  file=$2
  value=$(grep $key $file)
  # get value
  value=${value##*@@$key:}
  # trim spaces
  value=$(tr -d ' ' <<< $value)
  echo "$value"
}

# statistics
stat_pass=0
stat_fail=0
list_fail=""

update_pass()
{
  ((stat_pass = stat_pass + 1))
}
update_fail()
{
  ((stat_fail = stat_fail + 1))
}

# compile $input $output
compile()
{
  input=$1
  output=$2
  echo "Compiling $input" >>compile.log
  $CC $CXXFLAGS -c -o $2 $1 > /dev/null 2>>compile.log
}

# link $input $output
link()
{
  input=$1
  output=$2
  echo "Linking $input" >>compile.log
  $CC $CXXFLAGS $LXXFLAGS -o $2 $1 > /dev/null 2>>compile.log
}

# prints ok if output matches expected outcome
ok()
{
  printf "%-10s" "[OK]"
  printf "\n"
}

# prints fail if output does not match expected outcome
fail()
{
  printf "%-10s" "[FAIL]"
  printf "\n"
}

printcol()
{
  printf "%-11s %-30s" "$1:" "${!1}"
}

# combine frequently used together functions
ok_update()
{
  ok
  update_pass
}
fail_update()
{
  file=$1
  fail
  update_fail
  list_fail+="$file\n"
}

rm -f compile.log

for f in `ls *.c *.cpp`; do
  linkable=$(getValue "linkable" $f)
  compilable=$(getValue "compilable" $f)
  expect=$(getValue "expect" $f)

  filename="${f%.*}"

  # 1. Try to compile
  # 2. If compilation succeeds, try to link
  # 3. If linking succeeds, try to run

  printf "$f\n"

  if [ "$compilable" == "yes" ]; then
    printcol "compilable"
    compile $f $filename.o
    res=$?

    if [ $res -eq 0 ]; then
      ok

      if [ "$linkable" == "yes" ];  then
  
        printcol "linkable"
        link $filename.o $filename
        res=$?
  
        if [ $res -eq 0 ]; then
  	  ok
 
          if [ "$expect" == "success" ]; then
    
            printcol "expect"
            echo "Running $filename" >>compile.log
            ./$filename 2>&1 >>compile.log
            res=$?
    
    	    if [ $res -eq 0 ]; then
    	      ok_update
            else
              fail_update $f
            fi
          else
            # linkable pass, expect == no
            update_pass  
          fi
        else
          # linkable == yes, result == no
          fail_update $f
        fi
      else
        # compilable pass, linkable == no
        update_pass
      fi
    else
      # compilable == yes, result == no
      fail_update $f
    fi
  fi
  printf "\n"

done

# print stats
printf "%-20s %-10s" "Passed tests:" "$stat_pass"
printf "\n"
printf "%-20s %-10s" "Failed tests:" "$stat_fail"
printf "\n\n"
printf "Failed list:\n$list_fail"
echo "Check compile.log for details."
