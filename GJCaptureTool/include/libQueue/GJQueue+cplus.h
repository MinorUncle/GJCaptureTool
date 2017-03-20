//
//  GJQueue.h
//  GJQueue
//
//  Created by tongguan on 16/3/15.
//  Copyright © 2016年 MinorUncle. All rights reserved.
//


#ifndef GJQueue_cplus_h
#define GJQueue_cplus_h
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>
#include <sys/time.h>
#ifdef DEBUG
#define GJQueueLOG(format, ...) printf(format,##__VA_ARGS__)
#else
#define GJQueueLOG(format, ...)
#endif

#define DEFAULT_MAX_COUNT 3

#define DEFAULT_TIME 100000000


template <class T> class GJQueue{
    
private:
    T *buffer;
    long _inPointer;  //尾
    long _outPointer; //头
    int _capacity;
    int _allocSize;
    
    pthread_cond_t _inCond;
    pthread_cond_t _outCond;
    pthread_mutex_t _pushLock;
    pthread_mutex_t _popLock;
    
    bool _mutexInit();
    bool _mutexDestory();
    bool _condWait(pthread_cond_t* _cond,pthread_mutex_t* mutex,int ms = DEFAULT_TIME);
    bool _condSignal(pthread_cond_t* _cond);
    bool _condBroadcast(pthread_cond_t* _cond);
    
    bool _lock(pthread_mutex_t* mutex);
    bool _unLock(pthread_mutex_t* mutex);
    void _init();
    void _resize();
public:
    ~GJQueue(){
        _mutexDestory();
        free(buffer);
    };
    
#pragma mark DELEGATE
    //没有数据时是否支持等待，当为autoResize 为YES时，push永远不会等待
    bool autoResize;//是否支持自动增长，当为YES时，push永远不会等待，只会重新申请内存,默认为false
    
    
    bool queuePop(T* temBuffer,int ms=DEFAULT_TIME);
    bool queuePush(T temBuffer,int ms=DEFAULT_TIME);
    int currentLenth();
    
    //根据index获得vause,当超过_inPointer和_outPointer范围则失败，用于遍历数组，不会产生压出队列作用
    bool peekValueWithIndex(const long index,T* value);
    GJQueue(int capacity);
    GJQueue();
    void clean();
    
};

template<class T>
int GJQueue<T>::currentLenth(){
    
    return (int)(_outPointer - _inPointer);
}
template<class T>
GJQueue<T>::GJQueue()
{
    _capacity = DEFAULT_MAX_COUNT;
    _init();
}
template<class T>
GJQueue<T>::GJQueue(int capacity)
{
    _capacity = capacity;
    if (capacity <=0) {
        _capacity = DEFAULT_MAX_COUNT;
    }
    _init();
};

template<class T>
void GJQueue<T>::_init()
{
    buffer = (T*)malloc(sizeof(T)*_capacity);
    _allocSize = _capacity;
    autoResize = true;
    _inPointer = 0;
    _outPointer = 0;
    _mutexInit();
}
template<class T>
bool GJQueue<T>::peekValueWithIndex(const long index,T* value){
    if (index < _outPointer || index >= _inPointer) {
        return false;
    }
    long current = index%_allocSize;
    *value = buffer[current];
    return true;
}
/**
 *  深拷贝
 *
 *  @param temBuffer 用来接收推出的数据
 *
 *  @return 结果
 */
template<class T>
bool GJQueue<T>::queuePop(T* temBuffer,int ms){
    _lock(&_popLock);
    if (_inPointer <= _outPointer) {
        GJQueueLOG("begin Wait in ----------\n");
        if (!_condWait(&_outCond,&_popLock,ms)) {
            GJQueueLOG("fail Wait in ----------\n");
            _unLock(&_popLock);
            return false;
        }
        GJQueueLOG("after Wait in.  incount:%ld  outcount:%ld----------\n",_inPointer,_outPointer);
    }
    int index = _outPointer%_allocSize;
    *temBuffer = buffer[index];
    memset(&buffer[index], 0, sizeof(T));//防止在oc里的引用一直不释放；
    
    _outPointer++;
    _condSignal(&_inCond);
    GJQueueLOG("after signal out.  incount:%ld  outcount:%ld----------\n",_inPointer,_outPointer);
    _unLock(&_popLock);
//    assert(*temBuffer);
    return true;
}
template<class T>
bool GJQueue<T>::queuePush(T temBuffer,int ms){
    _lock(&_pushLock);
    if ((_inPointer % _allocSize == _outPointer % _allocSize && _inPointer > _outPointer)) {
        if (autoResize) {
            _resize();
        }else{
            
            GJQueueLOG("begin Wait out ----------\n");
            if (!_condWait(&_inCond,&_pushLock,ms)) {
                GJQueueLOG("fail begin Wait out ----------\n");
                _unLock(&_pushLock);
                return false;
            }
            GJQueueLOG("after Wait out.  incount:%ld  outcount:%ld----------\n",_inPointer,_outPointer);
        }
    }
    buffer[_inPointer%_allocSize] = temBuffer;
    _inPointer++;
    _condSignal(&_outCond);
    GJQueueLOG("after signal in. incount:%ld  outcount:%ld----------\n",_inPointer,_outPointer);
    _unLock(&_pushLock);
//    assert(temBuffer);

    return true;
}

template<class T>
void GJQueue<T>::clean(){
    _lock(&_popLock);
    _condBroadcast(&_inCond);//确保可以锁住下一个
    _lock(&_pushLock);
    while (_outPointer<_inPointer) {
        memset(&buffer[_outPointer++%_allocSize], 0, sizeof(T));//防止在oc里的引用一直不释放；
    }
    _inPointer=_outPointer=0;
    _condBroadcast(&_inCond);
    _unLock(&_pushLock);
    _unLock(&_popLock);
}

template<class T>
bool GJQueue<T>::_mutexInit()
{

    
    pthread_condattr_t cond_attr;
    pthread_condattr_init(&cond_attr);
    pthread_cond_init(&_inCond, &cond_attr);
    pthread_cond_init(&_outCond, &cond_attr);
    pthread_mutex_init(&_popLock, NULL);
    pthread_mutex_init(&_pushLock, NULL);

    return true;
}

template<class T>
bool GJQueue<T>::_mutexDestory()
{

    pthread_cond_destroy(&_inCond);
    pthread_cond_destroy(&_outCond);
    pthread_mutex_destroy(&_popLock);
    pthread_mutex_destroy(&_pushLock);

    return true;
}
template<class T>
bool GJQueue<T>::_condWait(pthread_cond_t* _cond,pthread_mutex_t* mutex,int ms)
{

    struct timespec ts;
    struct timeval tv;
    struct timezone tz;
    gettimeofday(&tv, &tz);
    ms += tv.tv_usec / 1000;
    ts.tv_sec = tv.tv_sec + ms / 1000;
    ts.tv_nsec = ms % 1000 * 1000000;
    int ret = pthread_cond_timedwait(_cond, mutex, &ts);
    printf("ret:%d,,%d\n",ret,!ret);
    return !ret;
}

template<class T>
bool GJQueue<T>::_condSignal(pthread_cond_t* _cond)
{
   
    return !pthread_cond_signal(_cond);
}

template<class T>
bool GJQueue<T>::_condBroadcast(pthread_cond_t* _cond)
{
    
    return !pthread_cond_broadcast(_cond);
}

template<class T>
bool GJQueue<T>::_lock(pthread_mutex_t* mutex){

    return !pthread_mutex_lock(mutex);
}

template<class T>
bool GJQueue<T>::_unLock(pthread_mutex_t* mutex){

    return !pthread_mutex_unlock(mutex);
}
template<class T>
void GJQueue<T>::_resize(){
    
    T* temBuffer = (T*)malloc(sizeof(T)*(_allocSize + (_allocSize/_capacity)*_capacity));
    for (long i = _outPointer,j =0; i<_inPointer; i++,j++) {
        temBuffer[j] = buffer[i%_allocSize];
    }
    free(buffer);
    buffer = temBuffer;
    _inPointer = _allocSize;
    _outPointer = 0;
    _allocSize += _capacity;
}
#endif /* GJQueue_h */
