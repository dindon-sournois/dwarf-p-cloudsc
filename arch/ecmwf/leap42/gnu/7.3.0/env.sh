# (C) Copyright 1988- ECMWF.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation
# nor does it submit to any jurisdiction.

# Source me to get the correct configure/build/run environment

# Store tracing and disable (module is *way* too verbose)
{ tracing_=${-//[^x]/}; set +x; } 2>/dev/null

module_load() {
  echo "+ module load $1"
  module load $1
}
module_unload() {
  echo "+ module unload $1"
  module unload $1
}

# Unload to be certain
module_unload boost
module_unload intel
module_unload cmake
module_unload gnu
module_unload ecbuild
module_unload openmpi
module_unload hdf5
module_unload python3

# Load modules
module_load gnu/7.3.0
module_load boost/1.61.0
module_load cmake/3.19.5
module_load openmpi/4.0.3
module_load hdf5/1.10.6
module_load python3/3.8.8-01

set -x

# Increase stack size to maximum
ulimit -S -s unlimited

# Restore tracing to stored setting
if [[ -n "$tracing_" ]]; then set -x; else set +x; fi

export ECBUILD_TOOLCHAIN="./toolchain.cmake"
