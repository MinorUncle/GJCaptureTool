#!/bin/sh

shellConfig=${0%/*}/Config.xcconfig

GROUP="avutil"



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
StaticFile=`pwd`/staticFile.txt
rubyFile=`pwd`/PraseProduct.rb
echo "PROJECT_DIR=${PROJECT_DIR}" > $shellConfig
echo "TARGETNAME=${TARGETNAME}" >> $shellConfig
echo "PROJECT_FILE_PATH=${PROJECT_FILE_PATH}" >> $shellConfig
echo "GROUP=${TARGETNAME}/lib${TARGETNAME}" >> $shellConfig
echo "arch=${arch}" >> $shellConfig
echo "StaticFile=${StaticFile}" >> $shellConfig
echo "rubyFile=${rubyFile}" >> $shellConfig

echo "${TARGETNAME}:then, please run currentPrase file out of xcode"
exit 1
fi


ruby $rubyFile $GROUP $TARGETNAME $PROJECT_FILE_PATH $StaticFile
echo "DidBuild=yes" >> $shellConfig
exit 1
