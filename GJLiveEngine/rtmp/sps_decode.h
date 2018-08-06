/**
 * Simplest Librtmp Send 264
 *
 * �����裬����
 * leixiaohua1020@126.com
 * zhanghuicuc@gmail.com
 * �й���ý��ѧ/���ֵ��Ӽ���
 * Communication University of China / Digital TV Technology
 * http://blog.csdn.net/leixiaohua1020
 *
 * ���������ڽ��ڴ��е�H.264����������RTMP��ý���������
 *
 */
#ifndef SPS_DECODE_H
#define SPS_DECODE_H
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
typedef  unsigned int UINT;
typedef  unsigned char BYTE;
typedef  unsigned long DWORD;

//pp��i֡���i֡,isKeyʱΪi֡,,����̫�࣬������ppSize���ķ�ʱ�䣬��ֱ���������,size�����ָ���
void find_pp_sps_pps(int *isKey, uint8_t* data,int size,uint8_t **pp,uint8_t **sps,int *spsSize,uint8_t** pps,int *ppsSize,uint8_t** sei,int *seiSize);
int h264_decode_sps(BYTE * buf,unsigned int nLen,int* width,int* height,int* fps);
int aac_parse_header(uint8_t *adts, int size,int* samples,int* objType,int* channel_config);
#endif
