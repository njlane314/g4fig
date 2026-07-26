cmake_minimum_required(VERSION 3.16)

project(g4fig VERSION 0.1.0 LANGUAGES CXX)

find_package(Geant4 REQUIRED gdml)

add_executable(g4fig src/g4fig.cc)
target_compile_features(g4fig PRIVATE cxx_std_17)
target_link_libraries(g4fig PRIVATE ${Geant4_LIBRARIES})
target_include_directories(g4fig PRIVATE ${Geant4_INCLUDE_DIRS})
target_compile_definitions(g4fig PRIVATE G4FIG_VERSION="${PROJECT_VERSION}")
target_compile_options(g4fig PRIVATE -Wall -Wextra -Wpedantic)

include(GNUInstallDirs)
install(TARGETS g4fig RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
