/*sigmoid function
* Author    : Huang Daoji
* StudentID : 1600017857
* Date      : 2018-04-16
*/

// header files
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <cuda_runtime.h>

#define M_PI_2        1.57079632679489661923	/* pi/2 */
#define M_PI_2_INV    (1.0/M_PI_2)
#define M_2_SQRTPI    1.12837916709551257390    /* 2/sqrt(pi) */
#define ERF_COEF      (1.0/M_2_SQRTPI)
#define threhold      1000000
#define SIZE          100000

const char* FILE_NAME = "homework2-input";


void verification(double* input, int size) {
	double ans = 0.0;
	for (int i = 0; i < size; i += 1) {
		ans += 1 / (1 + exp(-input[i]));
	}
	printf("result on cpu: %10.10f. \n", ans);
	return;
}

// print some basic parameters
void printDeviceProp(const cudaDeviceProp &prop) {
	printf("Device Name : %s.\n", prop.name);
	printf("totalGlobalMem : %d.\n", prop.totalGlobalMem);
	printf("sharedMemPerBlock : %d.\n", prop.sharedMemPerBlock);
	printf("regsPerBlock : %d.\n", prop.regsPerBlock);
	printf("warpSize : %d.\n", prop.warpSize);
	printf("memPitch : %d.\n", prop.memPitch);
	printf("maxThreadsPerBlock : %d.\n", prop.maxThreadsPerBlock);
	printf("maxThreadsDim[0 - 2] : %d %d %d.\n", prop.maxThreadsDim[0], prop.maxThreadsDim[1], prop.maxThreadsDim[2]);
	printf("maxGridSize[0 - 2] : %d %d %d.\n", prop.maxGridSize[0], prop.maxGridSize[1], prop.maxGridSize[2]);
	printf("totalConstMem : %d.\n", prop.totalConstMem);
	printf("major.minor : %d.%d.\n", prop.major, prop.minor);
	printf("clockRate : %d.\n", prop.clockRate);
	printf("textureAlignment : %d.\n", prop.textureAlignment);
	printf("deviceOverlap : %d.\n", prop.deviceOverlap);
	printf("multiProcessorCount : %d.\n", prop.multiProcessorCount);
}

// find a device, and quit
bool InitCUDA()
{
	int count;
	cudaGetDeviceCount(&count);

	if (count == 0) {
		fprintf(stderr, "There is no device.\n");
		return false;
	}

	int i;
	for (i = 0; i < count; i++) {
		cudaDeviceProp prop;
		cudaGetDeviceProperties(&prop, i);
		printDeviceProp(prop);
		if (cudaGetDeviceProperties(&prop, i) == cudaSuccess) {
			if (prop.major >= 1) {
				break;
			}
		}
	}

	if (i == count) {
		fprintf(stderr, "There is no device supporting CUDA 1.x.\n");
		return false;
	}
	cudaSetDevice(i);
	return true;
}


// kernel function here
__global__ static void calc(double* gpuans, double* gpuinput) {
	__shared__ double tmp[100];
	int bid = blockIdx.x * 10 + blockIdx.y;
	int tid = threadIdx.x * 10 + threadIdx.y;

	int tidx = bid * 1000 + tid * 10;
	tmp[tid] = 0;
	for (int i = 0; i < 10; i += 1) {
		double idx = gpuinput[tidx + i]; // base line inplementation <-- cache it!
		if (idx < threhold) {
			tmp[tid] = tmp[tid] + 1 / (1 + exp(-idx));
		}
		else {
            // could it be faster?
			tmp[tid] = tmp[tid] + M_PI_2_INV * atan(M_PI_2 * (idx));
		}
	}
	__syncthreads();

    // rubbish code
	if (tid > 63) {
		tmp[tid - 36] = tmp[tid] + tmp[tid - 36];
	}
	__syncthreads();
	int i = 32;
	while (i != 0) {
		if (tid < i) {
			tmp[tid] = tmp[tid + i] + tmp[tid];
		}
		__syncthreads();
		i /= 2;
	}
	if (tid == 0) {
		gpuans[bid] = tmp[0];
	}
}

void read_input(double* input, int size) {
    //what if choosing mmap()?
	FILE* fp = fopen(FILE_NAME, "r");
	if (fp) {
		for (int i = 0; i < size; i += 1) {
			fscanf(fp, "%lf\n", &input[i]);
		}
	}
	else {
		printf("error: reading input, in read_input()\n");
	}
}

int main() {
	if (!InitCUDA()) {
		return 0;
	}

	// warmup
	double* warmup = (double*)malloc(sizeof(double) * 1024 * 1024);
	double* gpuwarmup;
	cudaMalloc((void**)&gpuwarmup, sizeof(double) * 1024 * 1024);
	cudaMemcpy(gpuwarmup, warmup, sizeof(double) * 1024 * 1024, cudaMemcpyHostToDevice);
	free(warmup);
	cudaFree(gpuwarmup);

	//
	dim3 dimBlock(10, 10);
	dim3 dimGrid(10, 10);

	clock_t start, stop;
	start = clock();

	double* input = (double*)malloc(sizeof(double) * SIZE);
	double* gpuinput;
	cudaMalloc((void**)&gpuinput, sizeof(double) * SIZE);
	read_input(input, SIZE);
	cudaMemcpy(gpuinput, input, sizeof(double) * SIZE, cudaMemcpyHostToDevice);

	double* ans = (double*)calloc(100, sizeof(double));
	double* gpuans;
	cudaMalloc((void**)&gpuans, sizeof(double) * 100);
	cudaMemcpy(gpuans, ans, sizeof(double) * 100, cudaMemcpyHostToDevice);
	calc << <dimGrid, dimBlock >> >(gpuans, gpuinput);
	cudaMemcpy(ans, gpuans, sizeof(double) * 100, cudaMemcpyDeviceToHost);

	double res = 0.0;
	for (int i = 0; i < 100; i += 1) {
		res += ans[i];
	}

	cudaFree(gpuans);
    free(ans);
	cudaFree(gpuinput);
	stop = clock();
	double t_ns = (stop - start) / (double)(CLOCKS_PER_SEC);
	printf("%10.10f s\n", t_ns);
	printf("result is: %10.10f. \n", res);
	verification(input, SIZE);
	free(input);
	scanf("%ld", res);
	return 0;
}

/* end */