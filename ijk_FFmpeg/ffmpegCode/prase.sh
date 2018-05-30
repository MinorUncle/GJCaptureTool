#!/bin/sh



#default value


while read line
do
    for word in $line
    do
        if [ "${word}x" = "//x" ];then
        continue
        fi
        config_key=${word%=*}
        config_value="${word#*=}"
        eval "$config_key=$config_value"
    done
done < $shellConfig


if [ $DidBuild -a "yes" ];then
echo "Did build"
exit 0
fi


###in xcode  generate variable
if [ "${XCODE_PRODUCT_BUILD_VERSION}x" != "x" ];then
    #####need $PROJECT_DIR $TARGETNAME $PROJECT_FILE_PATH   $$$$
    configFile=${PROJECT_DIR}/ffmpegCode/config_${arch}.h
    makeFile=${PROJECT_DIR}/ffmpegCode/ffmpeg/lib${TARGETNAME}/Makefile
    echo "PROJECT_DIR=${PROJECT_DIR}" > $shellConfig
    echo "TARGETNAME=${TARGETNAME}" >> $shellConfig
    echo "PROJECT_FILE_PATH=${PROJECT_FILE_PATH}" >> $shellConfig
    echo "GROUP=${TARGETNAME}/lib${TARGETNAME}" >> $shellConfig
    echo "arch=${arch}" >> $shellConfig
    echo "configFile=${configFile}" >> $shellConfig
    echo "makeFile=${makeFile}" >> $shellConfig

    echo "${TARGETNAME}:then, please run currentPrase file out of xcode"
    exit 1
fi



echo "PROJECT_DIR:$PROJECT_DIR"
echo "PROJECT_FILE_PATH:$PROJECT_FILE_PATH"
echo "TARGETNAME:$TARGETNAME"

if [ "${PROJECT_DIR}x" = "x" ];then
echo "please frist run currentPrase file in xcode"
exit 1
fi





#define

Pre="OBJS-\$("
NeonPre="NEON-OBJS-\$("
Obj="OBJS"

echo "configFile:${configFile}"
echo "configFile:${configFile}"
echo "makeFile:${makeFile}"


#prase config

while read line
do
    line=($line)
    num=${#line[*]}
    if [ $num -eq 3  -a  "${line[0]}" = "#define" ];then
        config_key=${line[1]}
        config_value=${line[2]}
        eval "$config_key=$config_value"
    fi
done < $configFile


addFile(){
    outPutArry=($output)
    indexFind=0
    arryChange=0
    for index in ${!outPutArry[*]}
    do
        item=${outPutArry[$index]}
        itemKey=${item%:*}
        if [ "${itemKey}x" = "${1}x" ];then
        itemValue=${item#*:}
        indexFind=1

        if [ $itemValue -eq 0 -a $2 -eq 1 ];then
            outPutArry[$index]="${itemKey}:1"
            arryChange=1
        fi
        break
        fi
    done

    if [ $indexFind -eq 0 ];then
        addItem="${1}:${2}"
        arryLenth=${#outPutArry[*]}
        outPutArry[$arryLenth]=$addItem
        arryChange=1
    fi

    if [ $arryChange -eq 1 ];then
        temValue=""
        for indexValue in ${outPutArry[@]}
        do
            temValue="$temValue $indexValue"
        done
        echo $temValue
    else
        echo $output
    fi
}

#output=`addFile key4 1`
#echo $output
#exit 1
while read line
do
    key=0
    #match makefile是否找到key。findMatch  config中是否找到key，-1未匹配，1匹配为真，0匹配为假
    match=0
    findMatch=-1

    for word in $line
    do
        if [ $match -eq 1 -a $word != "+=" -a $word != "=" ];then
            negativeFlg=0
            if [ `echo $key | grep ^!` ];then
                #!开头取反标志
                key=${key:1}
                negativeFlg=1
            fi

            if [ $findMatch -eq -1 ];then
                findMatch=$(eval echo \$$key)
                #                findMatch=`findMatchFlag $key`
            fi

            if test -z "$findMatch"
            then
                findMatch=2
            fi

            if [ $negativeFlg -eq 1 ];then
            #!开头取反
                if [ $findMatch -eq 1 ];then
                findMatch=0
                elif [ $findMatch -eq 0 ];then
                findMatch=1
                fi
            fi

            word=${word#*/}
            preWord=${word%".o"}
            word=${preWord}.$expand
            echo  "${key}  ${word}   ${findMatch}"
            output=`addFile ${word} ${findMatch}`
            #            output="$output ${word}:${findMatch}"
        elif [ $word = $Obj ];then
            #一定添加NeonPre
            match=1
            key=$word
            findMatch=1
        elif [ `echo $word | grep ^${Pre}` ];then
            match=1
            key="${word#$Pre}"
            key=${key%)}
            findMatch=-1
            expand=c
        elif [ `echo $word | grep ^${NeonPre}` ];then
            match=1
            key="${word#$NeonPre}"
            key=${key%)}
            findMatch=-1
            expand=S
        else continue
        fi
    done
done < $makeFile


output="${GROUP} ${TARGETNAME} ${PROJECT_FILE_PATH} ${output}"
echo $output
rubyFile=${0%/*}
rubyFile=${rubyFile}/configProject.rb
ruby $rubyFile $output
echo "DidBuild=yes" >> $shellConfig
