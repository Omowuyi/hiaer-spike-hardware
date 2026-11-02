#!/usr/bin/env python3


from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
import os

dir_path = os.path.dirname(os.path.realpath(__file__))
include_dir = os.path.join(dir_path,'include')
lib_dir = os.path.join(dir_path,'linux','obj')


extensions = [
    Extension('dmadump', ['adxdma_dmadump.cpp','dmadump.pyx'], include_dirs = [include_dir,dir_path],language="c++",library_dirs = [lib_dir,dir_path],
                libraries=['adxdma']),
    ]


print(include_dir)
setup(
    ext_modules=cythonize(extensions),
)
