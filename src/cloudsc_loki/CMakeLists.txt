# (C) Copyright 1988- ECMWF.
#
# This software is licensed under the terms of the Apache Licence Version 2.0
# which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
# In applying this licence, ECMWF does not waive the privileges and immunities
# granted to it by virtue of its status as an intergovernmental organisation
# nor does it submit to any jurisdiction.

# Define this dwarf variant as an ECBuild feature
ecbuild_add_option( FEATURE CLOUDSC_LOKI
    DESCRIPTION "Use Loki source-to-source transformations with CLOUDSC " DEFAULT OFF
    CONDITION Serialbox_FOUND OR HDF5_FOUND
)

if( HAVE_CLOUDSC_LOKI )

    ####################################################
    ##  Define various pre-processing modes via Loki  ##
    ####################################################

    set( COMMON_MODULE "${CMAKE_CURRENT_SOURCE_DIR}/../common/module" )
    set( COMMON_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/../common/include" )
    set( XMOD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/xmod" )

    set( LOKI_FRONTEND "fp" CACHE STRING "Frontend parser for Loki transforms" )

    # OFP frontend cannot deal with statement functions, so we toggle them here
    set( CLOUDSC_DEFINE_STMT_FUNC "" )
    if(NOT "${LOKI_FRONTEND}" STREQUAL "ofp")
      set( CLOUDSC_DEFINE_STMT_FUNC CLOUDSC_STMT_FUNC )
    endif()

    if( TARGET clawfc AND ${LOKI_FRONTEND} STREQUAL "omni" )

        # Ugly hack: OMNI needs the xmod-file for cloudsc.F90 to be able to
        # parse the driver file successfully. However, the scheduler currently
        # doesn't take this into account and fails when parsing driver before
        # kernel file.
        # (Note: the problem vanishes in serial builds as there the C-transpile
        # target is built first which doesn't use the scheduler and therefore
        # creates the necessary xmod files for us)
        # TODO: This can be removed once the scheduler is aware of these dependencies
        # and parses files in the right order

        generate_xmod(
            OUTPUT ${XMOD_DIR}/cloudsc.xml
            SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc.F90
            XMOD ${XMOD_DIR}
        )

        # Use XML files as dependencies (not xmod) as they are updated by later calls of
        # F_Front (and thus would trigger new execution rounds)
        set( _OMNI_DEPENDENCIES ${XMOD_DIR}/cloudsc.xml )

    else()

        set( _OMNI_DEPENDENCIES )

    endif()

    ####################################################
    ##  Idempotence mode:                             ##
    ##   * Internal "do-nothing" mode for Loki debug  ##
    ####################################################

    loki_transform_convert(
        MODE idem FRONTEND ${LOKI_FRONTEND} CPP
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
        PATH ${CMAKE_CURRENT_SOURCE_DIR}
        HEADER ${COMMON_MODULE}/yomphyder.F90
        INCLUDE ${COMMON_INCLUDE}
        XMOD ${XMOD_DIR}
        OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-idem
        OUTPUT loki-idem/cloudsc.idem.F90 loki-idem/cloudsc_driver_loki_mod.idem.F90
        DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
    )

    ecbuild_add_executable( TARGET dwarf-cloudsc-loki-idem
        SOURCES
            dwarf_cloudsc.F90
            loki-idem/cloudsc_driver_loki_mod.idem.F90
            loki-idem/cloudsc.idem.F90
        DEFINITIONS ${CLOUDSC_DEFINITIONS}
    )
    target_link_libraries( dwarf-cloudsc-loki-idem PRIVATE cloudsc-common-lib )
    if( TARGET OpenMP::OpenMP_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-idem PRIVATE OpenMP::OpenMP_Fortran )
    endif()


    ####################################################
    ##  SCA mode (Single Column Abstraction):         ##
    ##   * Extract de-vectorized SCA format code      ##
    ####################################################

    loki_transform_convert(
        MODE sca FRONTEND ${LOKI_FRONTEND} CPP
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
        PATH ${CMAKE_CURRENT_SOURCE_DIR}
        HEADER ${COMMON_MODULE}/yomphyder.F90
        INCLUDE ${COMMON_INCLUDE}
        XMOD ${XMOD_DIR}
        OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-sca
        OUTPUT loki-sca/cloudsc.sca.F90 loki-sca/cloudsc_driver_loki_mod.sca.F90
        DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
    )

    ecbuild_add_executable( TARGET dwarf-cloudsc-loki-sca
        SOURCES
            dwarf_cloudsc.F90
            loki-sca/cloudsc_driver_loki_mod.sca.F90
            loki-sca/cloudsc.sca.F90
        DEFINITIONS ${CLOUDSC_DEFINITIONS}
    )
    target_link_libraries( dwarf-cloudsc-loki-sca PRIVATE cloudsc-common-lib )
    if( TARGET OpenMP::OpenMP_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-sca PRIVATE OpenMP::OpenMP_Fortran )
    endif()


    ####################################################
    ##  CLAW-CPU mode:                                ##
    ##   * Generate SCA code with CLAW annotations    ##
    ##   * Process with CLAW (CPU layout and OpenMP)  ##
    ####################################################
    if( TARGET clawfc )

        loki_transform_convert(
            MODE claw FRONTEND ${LOKI_FRONTEND} CPP
            CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
            PATH ${CMAKE_CURRENT_SOURCE_DIR}
            HEADER ${COMMON_MODULE}/yomphyder.F90
            INCLUDE ${COMMON_INCLUDE}
            XMOD ${XMOD_DIR}
            OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-claw-cpu
            OUTPUT loki-claw-cpu/cloudsc.claw.F90 loki-claw-cpu/cloudsc_driver_loki_mod.claw.F90
            DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
        )

        # We purposefully suppress CLAWs insertion of OpenMP loops,
        # as they are already present in the outer driver.
        claw_compile(
            MODEL_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/claw_cloudsc.config
            TARGET cpu DIRECTIVE none
            INCLUDE ${COMMON_INCLUDE}
            XMOD ${XMOD_DIR}
            SOURCE loki-claw-cpu/cloudsc.claw.F90
            OUTPUT loki-claw-cpu/cloudsc.claw.cpu.F90
        )
        claw_compile(
            MODEL_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/claw_cloudsc.config
            TARGET cpu DIRECTIVE none
            INCLUDE ${COMMON_INCLUDE}
            XMOD ${XMOD_DIR}
            SOURCE loki-claw-cpu/cloudsc_driver_loki_mod.claw.F90
            OUTPUT loki-claw-cpu/cloudsc_driver_loki_mod.claw.cpu.F90
            DEPENDS loki-claw-cpu/cloudsc.claw.cpu.F90
        )

        ecbuild_add_executable( TARGET dwarf-cloudsc-loki-claw-cpu
            SOURCES
                dwarf_cloudsc.F90
                loki-claw-cpu/cloudsc_driver_loki_mod.claw.cpu.F90
                loki-claw-cpu/cloudsc.claw.cpu.F90
            DEFINITIONS ${CLOUDSC_DEFINITIONS}
        )
        target_link_libraries( dwarf-cloudsc-loki-claw-cpu PRIVATE cloudsc-common-lib )
        if( TARGET OpenMP::OpenMP_Fortran )
            target_link_libraries( dwarf-cloudsc-loki-claw-cpu PRIVATE OpenMP::OpenMP_Fortran )
        endif()
    endif()

    ####################################################
    ##  CLAW-GPU mode:                                ##
    ##   * Generate SCA code with CLAW annotations    ##
    ##   * Process with CLAW (GPU layout and OpenACC) ##
    ####################################################
    if( TARGET clawfc )

        # Uses Loki-frontend CPP to switch to statement function variant again,
        # but suppresses inlining of stmt funcs by omitting `--include`
        loki_transform_convert(
            MODE claw FRONTEND ${LOKI_FRONTEND} CPP
            CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
            PATH ${CMAKE_CURRENT_SOURCE_DIR}
            HEADER ${COMMON_MODULE}/yomphyder.F90
            INCLUDE ${COMMON_INCLUDE}
            DEFINE CLOUDSC_GPU_TIMING ${CLOUDSC_DEFINE_STMT_FUNC}
            DATA_OFFLOAD REMOVE_OPENMP
            XMOD ${XMOD_DIR}
            OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-claw-gpu
            OUTPUT loki-claw-gpu/cloudsc.claw.F90 loki-claw-gpu/cloudsc_driver_loki_mod.claw.F90
            DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
        )

        claw_compile(
            MODEL_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/claw_cloudsc.config
            TARGET gpu DIRECTIVE openacc
            INCLUDE ${COMMON_INCLUDE}
            XMOD ${XMOD_DIR}
            SOURCE loki-claw-gpu/cloudsc.claw.F90
            OUTPUT loki-claw-gpu/cloudsc.claw.gpu.F90
        )
        claw_compile(
            MODEL_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/claw_cloudsc.config
            TARGET gpu DIRECTIVE openacc
            INCLUDE ${COMMON_INCLUDE}
            XMOD ${XMOD_DIR}
            SOURCE loki-claw-gpu/cloudsc_driver_loki_mod.claw.F90
            OUTPUT loki-claw-gpu/cloudsc_driver_loki_mod.claw.gpu.F90
            DEPENDS loki-claw-gpu/cloudsc.claw.gpu.F90
        )

        ecbuild_add_executable( TARGET dwarf-cloudsc-loki-claw-gpu
            SOURCES
                dwarf_cloudsc.F90
                loki-claw-gpu/cloudsc_driver_loki_mod.claw.gpu.F90
                loki-claw-gpu/cloudsc.claw.gpu.F90
            DEFINITIONS ${CLOUDSC_DEFINITIONS}
        )
        if( TARGET OpenMP::OpenMP_Fortran )
            target_link_libraries( dwarf-cloudsc-loki-claw-gpu PRIVATE OpenMP::OpenMP_Fortran )
        endif()
        if( TARGET OpenACC::OpenACC_Fortran )
            target_link_libraries( dwarf-cloudsc-loki-claw-gpu PRIVATE OpenACC::OpenACC_Fortran )
            target_link_libraries( dwarf-cloudsc-loki-claw-gpu PRIVATE cloudsc-common-lib-static )
        else()
            target_link_libraries( dwarf-cloudsc-loki-claw-gpu PRIVATE cloudsc-common-lib )
        endif()
    endif()


    ####################################################
    ##  "Single Column Coalesced" (SCC) mode          ##
    ##   * Removes horizontal vector loops            ##
    ##   * Invokes compute kernel as `!$acc vector`   ##
    ####################################################

    loki_transform_convert(
        MODE scc FRONTEND ${LOKI_FRONTEND} CPP
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
        PATH ${CMAKE_CURRENT_SOURCE_DIR}
        HEADER ${COMMON_MODULE}/yomphyder.F90
        INCLUDE ${COMMON_INCLUDE}
        DEFINE CLOUDSC_GPU_TIMING ${CLOUDSC_DEFINE_STMT_FUNC}
        DATA_OFFLOAD REMOVE_OPENMP
        XMOD ${XMOD_DIR}
        OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-scc
        OUTPUT loki-scc/cloudsc.scc.F90 loki-scc/cloudsc_driver_loki_mod.scc.F90
        DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
    )

    ecbuild_add_executable( TARGET dwarf-cloudsc-loki-scc
        SOURCES
            dwarf_cloudsc.F90
            loki-scc/cloudsc_driver_loki_mod.scc.F90
            loki-scc/cloudsc.scc.F90
        DEFINITIONS ${CLOUDSC_DEFINITIONS}
    )
    if( TARGET OpenMP::OpenMP_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc PRIVATE OpenMP::OpenMP_Fortran )
    endif()
    if( TARGET OpenACC::OpenACC_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc PRIVATE OpenACC::OpenACC_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc PRIVATE cloudsc-common-lib-static )
    else()
        target_link_libraries( dwarf-cloudsc-loki-scc PRIVATE cloudsc-common-lib )
    endif()


    ####################################################
    ##  SCC-hoist mode                                ##
    ##   * SCC with vector loop hoisted               ##
    ##   * Kernel is "seq, but args are full blocks   ##
    ##   * Temporary arrays hoisted to driver         ##
    ####################################################

    loki_transform_convert(
        MODE scc-hoist FRONTEND ${LOKI_FRONTEND} CPP
        CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_loki.config
        PATH ${CMAKE_CURRENT_SOURCE_DIR}
        HEADER ${COMMON_MODULE}/yomphyder.F90
        INCLUDE ${COMMON_INCLUDE}
        DEFINE CLOUDSC_GPU_TIMING ${CLOUDSC_DEFINE_STMT_FUNC}
        DATA_OFFLOAD REMOVE_OPENMP
        XMOD ${XMOD_DIR}
        OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-scc-hoist
        OUTPUT
            loki-scc-hoist/cloudsc.scc_hoist.F90
            loki-scc-hoist/cloudsc_driver_loki_mod.scc_hoist.F90
        DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
    )

    ecbuild_add_executable( TARGET dwarf-cloudsc-loki-scc-hoist
        SOURCES
            dwarf_cloudsc.F90
            loki-scc-hoist/cloudsc_driver_loki_mod.scc_hoist.F90
            loki-scc-hoist/cloudsc.scc_hoist.F90
        DEFINITIONS ${CLOUDSC_DEFINITIONS}
    )
    if( TARGET OpenMP::OpenMP_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc-hoist PRIVATE OpenMP::OpenMP_Fortran )
    endif()
    if( TARGET OpenACC::OpenACC_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc-hoist PRIVATE OpenACC::OpenACC_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-scc-hoist PRIVATE cloudsc-common-lib-static )
    else()
        target_link_libraries( dwarf-cloudsc-loki-scc-hoist PRIVATE cloudsc-common-lib )
    endif()


    ##############################################################################
    # C-transpilation mode for generating vectorized C host code (experimental!)
    ##############################################################################

    loki_transform_transpile(
        FRONTEND ${LOKI_FRONTEND} CPP
        HEADER
            ${COMMON_MODULE}/parkind1.F90
            ${COMMON_MODULE}/yomphyder.F90
            ${COMMON_MODULE}/yomcst.F90
            ${COMMON_MODULE}/yoethf.F90
            ${COMMON_MODULE}/yoecldp.F90
            ${COMMON_MODULE}/fcttre_mod.F90
            ${COMMON_MODULE}/fccld_mod.F90
        DRIVER ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc_driver_loki_mod.F90
        SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/cloudsc.F90
        INCLUDE ${COMMON_INCLUDE}
        XMOD ${XMOD_DIR}
        OUTPATH ${CMAKE_CURRENT_BINARY_DIR}/loki-c
        OUTPUT
            loki-c/cloudsc_driver_loki_mod.c.F90
            loki-c/cloudsc_fc.F90 loki-c/cloudsc_c.c
            loki-c/yoethf_fc.F90 loki-c/yomcst_fc.F90
            loki-c/yoecldp_fc.F90
        DEPENDS cloudsc.F90 cloudsc_driver_loki_mod.F90 ${_OMNI_DEPENDENCIES}
    )

    # Define the CLAW-CPU build target for this variant
    ecbuild_add_executable( TARGET dwarf-cloudsc-loki-c
        SOURCES
            dwarf_cloudsc.F90
            loki-c/cloudsc_driver_loki_mod.c.F90
            loki-c/cloudsc_fc.F90
            loki-c/cloudsc_c.c
            loki-c/yoethf_fc.F90
            loki-c/yomcst_fc.F90
            loki-c/yoecldp_fc.F90
        DEFINITIONS ${CLOUDSC_DEFINITIONS}
    )
    target_link_libraries( dwarf-cloudsc-loki-c PRIVATE cloudsc-common-lib )
    if( TARGET OpenMP::OpenMP_Fortran AND TARGET OpenMP::OpenMP_C )
        target_link_libraries( dwarf-cloudsc-loki-c PRIVATE OpenMP::OpenMP_Fortran )
        target_link_libraries( dwarf-cloudsc-loki-c PRIVATE OpenMP::OpenMP_C )
    endif()

    # Create symlink for the input data
    if( HAVE_SERIALBOX )
      execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink
          ${CMAKE_CURRENT_SOURCE_DIR}/../../data ${CMAKE_CURRENT_BINARY_DIR}/../../../data )
    endif()

    if( HAVE_HDF5 )
      execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink
          ${CMAKE_CURRENT_SOURCE_DIR}/../../config-files/input.h5 ${CMAKE_CURRENT_BINARY_DIR}/../../../input.h5 )
      execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink
          ${CMAKE_CURRENT_SOURCE_DIR}/../../config-files/reference.h5 ${CMAKE_CURRENT_BINARY_DIR}/../../../reference.h5 )
    endif()
endif()
