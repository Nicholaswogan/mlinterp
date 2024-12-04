from numpy cimport ndarray
import numpy as np
cimport numpy as np
from libc.stdlib cimport malloc, free

cdef extern void interp_vector(
  int n, int *nd, double **xd, double *fd,
  int ni, double *xi, double *fi
)

cdef extern void interp_single(
  int n, int *nd, double **xd, double *fd,
  double *xi, double *fi
)

cdef is_sorted(int n, double *a):
  cdef int i
  for i in range(n-1):
      if not a[i+1] > a[i]:
          return False
  return True

cdef class RegularGridInterpolator:
  """
  Interpolator on a regular or rectilinear grid in up to 10 dimensions.

  The data must be defined on a rectilinear grid; that is, a rectangular
  grid with even or uneven spacing. Only linear interpolation is
  supported.

  Parameters
  ----------
  points : tuple of ndarray of float, with shapes (m1, ), ..., (mn, )
      The points defining the regular grid in n dimensions. The points in
      each dimension (i.e. every elements of the points tuple) must be
      strictly ascending or descending.

  values : ndarray, shape (m1, ..., mn, ...)
      The data on the regular grid in n dimensions.
  """

  cdef double** xd
  cdef int n
  cdef int* nd
  cdef double* fd

  def __cinit__(self, *args, **kwargs):
    self.xd = NULL
    self.nd = NULL
    self.fd = NULL

  def __init__(self, tuple points, ndarray values):
    self.n = len(points)
    if self.n > 10:
      raise ValueError('`RegularGridInterpolator` can not interpolate greater than 10 dimensions.')
    self.nd = <int *> malloc(self.n * sizeof(int))
    self.xd = <double **> malloc(self.n * sizeof(double*))

    cdef sort
    cdef ndarray[double, ndim=1] tmp;
    cdef double *tmp_p;
    for i in range(self.n):
      tmp = points[i]
      tmp_p = <double *> tmp.data
      self.nd[i] = points[i].shape[0]
      assert self.nd[i] == values.shape[i], "Input `points` and `values` have incompatible shapes"
      self.xd[i] = <double *> malloc(self.nd[i] * sizeof(double))
      for j in range(self.nd[i]):
        self.xd[i][j] = tmp_p[j]
      sort = is_sorted(self.nd[i], self.xd[i])
      if not sort:
        raise ValueError('Some of the arrays in `points` are not sorted')

    assert values.dtype == np.double, "`values` must have have dtype `np.double`"
    cdef double *fd = <double *> values.data
    cdef int n1 = values.size
    self.fd = <double *> malloc(n1 * sizeof(double))
    for i in range(n1):
      self.fd[i] = fd[i]
    
  def __dealloc__(self):
    if self.xd:
      for i in range(self.n):
        free(self.xd[i])
      free(self.xd)
    if self.nd: 
      free(self.nd)
    if self.fd: 
      free(self.fd)

  def evaluate_vector(self, ndarray[double, ndim=2] xi):

    cdef int ni = xi.shape[0]
    assert xi.shape[1] == self.n, "Input `xi` has the wrong dimension"
    cdef ndarray[double,ndim=1] fi = np.empty(ni,np.double)

    cdef double *xi_p
    cdef ndarray[double,ndim=2] xi_copy
    if np.PyArray_IS_C_CONTIGUOUS(xi):
      xi_p = <double *> xi.data
    else:
      xi_copy = np.ascontiguousarray(xi)
      xi_p = <double *> xi_copy.data

    interp_vector(
      self.n, self.nd, self.xd, self.fd, 
      ni, xi_p, <double *> fi.data
    )
    return fi

  def evaluate(self, ndarray[double, ndim=1] xi):

    assert xi.shape[0] == self.n, "Input `xi` has the wrong dimension"
    cdef double fi

    cdef double *xi_p
    cdef ndarray[double,ndim=1] xi_copy
    if np.PyArray_IS_C_CONTIGUOUS(xi):
      xi_p = <double *> xi.data
    else:
      xi_copy = np.ascontiguousarray(xi)
      xi_p = <double *> xi_copy.data

    interp_single(
      self.n, self.nd, self.xd, self.fd, 
      xi_p, &fi
    )
    return fi

  def __call__(self, ndarray xi):
    """
    Interpolation at coordinates.

    Parameters
    ----------
    xi : ndarray
        The coordinates to evaluate the interpolator at.

    Returns
    -------
    fi : float
        Interpolated values at `xi`.
    """

    cdef double tmp;
    cdef ndarray[double,ndim=1] fi

    if xi.ndim == 1:
      tmp = self.evaluate(xi)
      fi = np.array([tmp])
    elif xi.ndim == 2:
      fi = self.evaluate_vector(xi)
    else:
      raise ValueError("`xi` must have 1 or two dimensions.")

    return fi