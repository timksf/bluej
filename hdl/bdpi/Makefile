
SOURCES_BDPI:=$(wildcard *.cc)
OBJECTS_BDPI := $(patsubst %.cc, %.o, $(SOURCES_BDPI))

CFLAGS=-fPIC -Wall

%.o : %.cc
	gcc $(CFLAGS) -c $< -o $@

all: $(OBJECTS_BDPI)
	echo "[BDPI] Compiled: $(OBJECTS_BDPI)"

clean: 
	rm -f *.o
