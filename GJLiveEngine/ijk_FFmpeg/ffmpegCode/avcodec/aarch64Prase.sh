#!/bin/sh

#  aarch64Prase.sh
#  ffmpegCode
#
#  Created by tongguan on 16/10/18.
#  Copyright © 2016年 MinorUncle. All rights reserved.
export shellConfig=${0%/*}/aarch64_Config.xcconfig



echo $PROJECT_FILE_PATH
if [ "${PROJECT_FILE_PATH}x" = "x" ];then
praseFile=${PWD}
praseFile=${praseFile%/*}/prase.sh
else
praseFile=${0%/*}
praseFile=${praseFile%/*}/prase.sh
fi


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

if [ "${XCODE_PRODUCT_BUILD_VERSION}x" != "x" ];then
configFile=${PROJECT_DIR}/ffmpegCode/config_${arch}.h
makeFile=${PROJECT_DIR}/ffmpegCode/ffmpeg/lib${TARGETNAME}/aarch64/Makefile
echo "PROJECT_DIR=${PROJECT_DIR}" > $shellConfig
echo "TARGETNAME=${TARGETNAME}" >> $shellConfig
echo "PROJECT_FILE_PATH=${PROJECT_FILE_PATH}" >> $shellConfig
echo "GROUP=${TARGETNAME}/lib${TARGETNAME}/aarch64" >> $shellConfig
echo "arch=${arch}" >> $shellConfig
echo "configFile=${configFile}" >> $shellConfig
echo "makeFile=${makeFile}" >> $shellConfig
cat $shellConfig
echo "then, please run aarch64Prase.sh out of xcode"
exit 1
else
echo $praseFile
exec $praseFile
fi
