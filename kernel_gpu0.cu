
#include <assert.h>
#include <stdio.h>

#include "kernel.h"
#include "matrix.h"
#include "timer.h"
#define threads 32
#define THRESHOLD 0.000001
#define YMAX 32

__global__ void spmspm(COOMatrix *result, CSRMatrix *A, CSCMatrix *B, float bias) {

    // TODO
	unsigned int r = blockIdx.y*blockDim.y + threadIdx.y;
	unsigned int c = blockIdx.x*blockDim.x + threadIdx.x;


	if (r < A->numRows && c < B->numCols) {
		unsigned int rowPtrA = A->rowPtrs[r];
		unsigned int nnzA = A->rowPtrs[r + 1] - rowPtrA;

		unsigned int colPtrB = B->colPtrs[c];
		unsigned int nnzB = B->colPtrs[c + 1] - colPtrB;
		if (nnzA > 0 && nnzB > 0) { // if a row is not all zeros , we do computation otherwise we skip row
                unsigned int* colIdxsA = A->colIdxs + rowPtrA;
                float* valueA = A->values + rowPtrA;
                unsigned int* rowIdxsB = B->rowIdxs + colPtrB;
                float* valueB = B->values + colPtrB;

                float sum = 0.0f;
                unsigned int ia = 0, ib = 0;
                while(ia < nnzA && ib < nnzB) {
                    unsigned int colIdx = colIdxsA[ia];
                    unsigned int rowIdx = rowIdxsB[ib];
                    if(colIdx < rowIdx) {
                        ia++;
                    } else if(colIdx > rowIdx) {
                        ib++;
                    } else {
                        sum += valueA[ia]*valueB[ib];
                        ia++;
                        ib++;
                    }
                }    


			//}
			if (sum > THRESHOLD || sum < -THRESHOLD) { //if not smaller than abs(threshold)
				sum += bias; //add to it the bias

				if (sum > 0) {//if end result is positive otherwise I also do not want to add it to result
					if (sum > YMAX) { //make sure it is on an upper limit
						sum = YMAX;
					}
					unsigned int nnzIndxTemp = atomicAdd(&(result->nnz), 1); //counts how many non zero elements I have
					result->rowIdxs[nnzIndxTemp] = r;
					result->colIdxs[nnzIndxTemp] = c;
					result->values[nnzIndxTemp] = sum;
				}
			}


		}
    }


}

void findNonzeroRows(Vector* v, CSRMatrix* A) {
    unsigned int nnz = 0;
    for(unsigned int r = 0; r < A->numRows; ++r) {
        unsigned int rowPtrA = A->rowPtrs[r];
        unsigned int nnzA = A->rowPtrs[r + 1] - rowPtrA;
        if(nnzA > 0) {
            if(nnz >= v->capacity) {
                expandVectorCapacity(v, 2*v->capacity);
            }
            v->data[nnz] = r;
            ++nnz;
        }
    }
    v->nnz = nnz;
}

COOMatrix* createEmptyCOO_d(unsigned int numRows, unsigned int numCols, unsigned int capacity) {
    COOMatrix cooShadow;
    cooShadow.numRows = numRows;
    cooShadow.numCols = numCols;
    cooShadow.nnz = 0;
    cooShadow.capacity = capacity;
    cudaMalloc((void**) &cooShadow.rowIdxs, capacity*sizeof(unsigned int));
    cudaMalloc((void**) &cooShadow.colIdxs, capacity*sizeof(unsigned int));
    cudaMalloc((void**) &cooShadow.values, capacity*sizeof(float));
    COOMatrix* coo_d;
    cudaMalloc((void**) &coo_d, sizeof(COOMatrix));
    cudaMemcpy(coo_d, &cooShadow, sizeof(COOMatrix), cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
    return coo_d;
}

void copyCOOfromGPU(COOMatrix* coo_d, COOMatrix* coo) {
    COOMatrix cooShadow;
    cudaMemcpy(&cooShadow, coo_d, sizeof(COOMatrix), cudaMemcpyDeviceToHost);
    assert(coo->numRows == cooShadow.numRows);
    assert(coo->numCols == cooShadow.numCols);
    assert(coo->capacity >= cooShadow.nnz);
    coo->nnz = cooShadow.nnz;
    cudaMemcpy(coo->rowIdxs, cooShadow.rowIdxs, cooShadow.nnz*sizeof(unsigned int), cudaMemcpyDeviceToHost);
    cudaMemcpy(coo->colIdxs, cooShadow.colIdxs, cooShadow.nnz*sizeof(unsigned int), cudaMemcpyDeviceToHost);
    cudaMemcpy(coo->values, cooShadow.values, cooShadow.nnz*sizeof(float), cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();
}

CSRMatrix* createEmptyCSR_d(unsigned int numRows, unsigned int numCols, unsigned int capacity) {
    CSRMatrix csrShadow;
    csrShadow.numRows = numRows;
    csrShadow.numCols = numCols;
    csrShadow.nnz = 0;
    csrShadow.capacity = capacity;
    cudaMalloc((void**) &csrShadow.rowPtrs, (numRows + 1)*sizeof(unsigned int));
    cudaMalloc((void**) &csrShadow.colIdxs, capacity*sizeof(unsigned int));
    cudaMalloc((void**) &csrShadow.values, capacity*sizeof(float));
    CSRMatrix* csr_d;
    cudaMalloc((void**) &csr_d, sizeof(CSRMatrix));
    cudaMemcpy(csr_d, &csrShadow, sizeof(CSRMatrix), cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
    return csr_d;
}

void copyCSRtoGPU(CSRMatrix* csr, CSRMatrix* csr_d) {
    CSRMatrix csrShadow;
    cudaMemcpy(&csrShadow, csr_d, sizeof(CSRMatrix), cudaMemcpyDeviceToHost);
    assert(csrShadow.numRows == csr->numRows);
    assert(csrShadow.numCols == csr->numCols);
    assert(csrShadow.capacity >= csr->nnz);
    csrShadow.nnz = csr->nnz;
    cudaMemcpy(csrShadow.rowPtrs, csr->rowPtrs, (csr->numRows + 1)*sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaMemcpy(csrShadow.colIdxs, csr->colIdxs, csr->nnz*sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaMemcpy(csrShadow.values, csr->values, csr->nnz*sizeof(float), cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
}

CSCMatrix* createCSCfromCSC_d(CSCMatrix* csc) {
    CSCMatrix cscShadow;
    cscShadow.numRows = csc->numRows;
    cscShadow.numCols = csc->numCols;
    cscShadow.nnz = csc->nnz;
    cscShadow.capacity = csc->capacity;
    cudaMalloc((void**) &cscShadow.colPtrs, (csc->numCols + 1)*sizeof(unsigned int));
    cudaMalloc((void**) &cscShadow.rowIdxs, csc->capacity*sizeof(unsigned int));
    cudaMalloc((void**) &cscShadow.values, csc->capacity*sizeof(float));
    cudaMemcpy(cscShadow.colPtrs, csc->colPtrs, (csc->numCols + 1)*sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaMemcpy(cscShadow.rowIdxs, csc->rowIdxs, csc->capacity*sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaMemcpy(cscShadow.values, csc->values, csc->capacity*sizeof(float), cudaMemcpyHostToDevice);
    CSCMatrix* csc_d;
    cudaMalloc((void**) &csc_d, sizeof(CSCMatrix));
    cudaMemcpy(csc_d, &cscShadow, sizeof(CSCMatrix), cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
    return csc_d;
}

void sparseNN(Vector* result, COOMatrix* featureVectors, COOMatrix** layerWeights, float bias, unsigned int numLayers) {

    Timer timer;

    // Convert featureVectors to CSR
    startTime(&timer);
    CSRMatrix* Y0 = createEmptyCSR(featureVectors->numRows, featureVectors->numCols, 4*featureVectors->nnz); // Assuming 4*nnz is enough for all Y vectors
    convertCOOtoCSR(featureVectors, Y0);
    CSRMatrix* Y0_d = createEmptyCSR_d(featureVectors->numRows, featureVectors->numCols, 4*featureVectors->nnz); // Assuming 4*nnz is enough for all Y vectors
    stopTimeAndPrint(&timer, "Convert feature vectors to CSR");

    // Convert layer weights to CSC
    startTime(&timer);
    CSCMatrix* W[numLayers];
    CSCMatrix* W_d[numLayers];
    for(unsigned int layer = 0; layer < numLayers; ++layer) {
        W[layer] = createCSCfromCOO(layerWeights[layer]);
        W_d[layer] = createCSCfromCSC_d(W[layer]);
    }
    stopTimeAndPrint(&timer, "Convert weights to CSR");

    // Temporary buffer
    startTime(&timer);
    COOMatrix *tmp = createEmptyCOO(Y0->numRows, Y0->numCols, Y0->capacity);
    COOMatrix *tmp_d = createEmptyCOO_d(Y0->numRows, Y0->numCols, Y0->capacity);
    stopTimeAndPrint(&timer, "Allocate temporary buffer");

    // Loop over layers
    CSRMatrix *Yin = Y0;
    COOMatrix *Yout = tmp;
    CSRMatrix *Yin_d = Y0_d;
    COOMatrix *Yout_d = tmp_d;
    for(unsigned int layer = 0; layer < numLayers; ++layer) {

        printf("Computing layer %u (SpMSpM)\n", layer);

        // Copy to GPU
        startTime(&timer);
        copyCSRtoGPU(Yin, Yin_d);
        cudaMemset(&Yout_d->nnz, 0, sizeof(unsigned int));
        stopTimeAndPrint(&timer, "    Copy CSR to GPU and clear COO");

        // SpMSpM
        startTime(&timer);
        // TODO: spmspm <<< ..., ... >>> (Yout_d, Yin_d, W_d[layer], bias);
        dim3 numThreadsPerBlock3(threads, threads);
		dim3 numBlocks3((W[layer]->numCols + numThreadsPerBlock3.x - 1) / numThreadsPerBlock3.x, (Y0->numRows + numThreadsPerBlock3.y - 1) / numThreadsPerBlock3.y);

		spmspm << <numBlocks3, numThreadsPerBlock3 >> > (Yout_d, Yin_d, W_d[layer], bias);

        cudaDeviceSynchronize();
        stopTimeAndPrint(&timer, "    SpMSpM");

        // Copy from GPU
        startTime(&timer);
        copyCOOfromGPU(Yout_d, Yout);
        stopTimeAndPrint(&timer, "    Copy COO from GPU");
        printf("    Output matrix number of nonzeros: %d\n", Yout->nnz);

        // Convert COO to CSR
        startTime(&timer);
        convertCOOtoCSR(Yout, Yin);
        stopTimeAndPrint(&timer, "    Converting COO to CSR");

    }

    // Find nonzero rows
    startTime(&timer);
    findNonzeroRows(result, Yin);
    stopTimeAndPrint(&timer, "Find nonzero rows");

    // Free buffers
    startTime(&timer);
    freeCSR(Y0);
    for(unsigned int layer = 0; layer < numLayers; ++layer) {
        freeCSC(W[layer]);
    }
    freeCOO(tmp);
    stopTimeAndPrint(&timer, "Deallocate memory");

}

