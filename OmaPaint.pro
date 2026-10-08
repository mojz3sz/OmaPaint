QT += core gui qml quick quickcontrols2 quickdialogs2

CONFIG += c++17

TEMPLATE = app
TARGET = omapaint

SOURCES += main.cpp
RESOURCES += qml.qrc

target.path = /usr/lib/omapaint
INSTALLS += target
