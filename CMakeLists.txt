cmake_minimum_required(VERSION 3.21)

project(OmaPaint LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 QuickDialogs2)

if (COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
endif()

qt_add_executable(omapaint main.cpp)

qt_add_qml_module(omapaint
    URI OmaPaint
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        quickpaint.qml
)

target_link_libraries(omapaint PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
)

install(TARGETS omapaint
    RUNTIME DESTINATION lib/omapaint
)
