import numpy as np
import time
from sklearn.neighbors import sort_graph_by_row_values
from scipy.sparse import csr_matrix, tril
from joblib import Parallel, delayed
import functools


def timer(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        end = time.time()
        print(f"{func.__name__}\t{end - start:f}")
        return result

    return wrapper


def sort_row(data_slice, indices_slice):
    order = np.argsort(data_slice, kind="mergesort")
    return data_slice[order], indices_slice[order]


def parallel_sort_rows(graph):
    # Get the slices of data and indices
    data_slices = [
        graph.data[start:stop]
        for start, stop in zip(graph.indptr[:-1], graph.indptr[1:])
    ]
    indices_slices = [
        graph.indices[start:stop]
        for start, stop in zip(graph.indptr[:-1], graph.indptr[1:])
    ]

    # Sort each slice in parallel
    sorted_slices = Parallel(n_jobs=-1)(
        delayed(sort_row)(data_slice, indices_slice)
        for data_slice, indices_slice in zip(data_slices, indices_slices)
    )

    # Update the graph with sorted slices
    for (start, stop), (sorted_data, sorted_indices) in zip(
        zip(graph.indptr[:-1], graph.indptr[1:]), sorted_slices
    ):
        graph.data[start:stop] = sorted_data
        graph.indices[start:stop] = sorted_indices

    return graph


def batch_update_numpy_distance_matrix(new_embeds, cluster_pool, batch_size=120):

    # Convert the vectors to NumPy arrays
    vectors_numpy = np.array(new_embeds)
    cluster_pool_numpy = np.array(cluster_pool)
    norms = np.linalg.norm(vectors_numpy, axis=1, keepdims=True)  # L2 Norm
    normalized_vectors = vectors_numpy / norms  # Unit vectors
    norms = np.linalg.norm(cluster_pool_numpy, axis=1, keepdims=True)  # L2 Norm
    normalized_pool = cluster_pool_numpy / norms

    # Initialize an empty similarity matrix
    distance_matrix = np.zeros(
        (len(vectors_numpy), len(cluster_pool_numpy)), dtype=np.float16
    )

    # Iterate through the vectors in batches
    for start in range(0, len(cluster_pool_numpy), batch_size):
        end = min(start + batch_size, len(cluster_pool_numpy))
        batch_cluster_pool = normalized_pool[start:end]

        # Compute cosine similarity for the batch
        similarity_batch = np.dot(normalized_vectors, batch_cluster_pool.T)

        # Convert similarity to distance
        distance_batch = 1 - similarity_batch

        # Fill in the corresponding section of the distance matrix
        distance_matrix[:, start:end] = distance_batch

    # Clip values to prevent numerical issues that might result in values slightly outside [0, 1]
    distance_matrix = np.clip(distance_matrix, 0, 1)

    return distance_matrix


def get_sparse_distance_matrix(dense, n_priors):

    values = dense.flatten().astype(np.float32)

    row_indices = [*range(0, dense.shape[1])] * dense.shape[0]

    column_pointers = [0] * (n_priors + 1) + [
        *range(dense.shape[1], dense.shape[0] * (dense.shape[1] + 1), dense.shape[1])
    ]

    sparse_matrix = csr_matrix(
        (values, row_indices, column_pointers), shape=(dense.shape[1], dense.shape[1])
    )
    sparse_matrix = make_symmetric(sparse_matrix=sparse_matrix)

    if n_priors < 15000:
        res = sort_graph_by_row_values(
            sparse_matrix, copy=True, warn_when_not_sorted=False
        )
    else:
        res = parallel_sort_rows(sparse_matrix)

    return res


def make_symmetric(sparse_matrix):

    low_tri = tril(sparse_matrix, k=0)
    symmetric_matrix = low_tri + tril(low_tri, k=-1).T

    return symmetric_matrix


def prep_for_streaming(documents, interval=40):

    # split for streaming
    doc_splits = {}

    aug_records = documents
    estimated_time = len(aug_records) / interval
    for j, i in enumerate(range(0, len(aug_records), interval)):
        doc_splits[j] = aug_records[i : i + interval]

    return doc_splits, estimated_time
