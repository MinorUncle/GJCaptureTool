#!/bin/sh

#  avformatPrase.sh
#  ffmpegCode
#
#  Created by tongguan on 16/10/8.
#  Copyright © 2016年 MinorUncle. All rights reserved.

export shellConfig=${0%/*}/Config.xcconfig
echo $PROJECT_FILE_PATH
if [ "${PROJECT_FILE_PATH}x" = "x" ];then
praseFile=${PWD}
praseFile=${praseFile%/*}/prase.sh
else
praseFile=${0%/*}
praseFile=${praseFile%/*}/prase.sh
fi

exec $praseFile
