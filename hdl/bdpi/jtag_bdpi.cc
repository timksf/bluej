#include <stdio.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET_NAME "/tmp/jtag.sock"

#ifdef __cplusplus
extern "C" {
#endif

int32_t c_socket_init() {
    int32_t socket_fd;
    int32_t ret;

    unlink(SOCKET_NAME);
    socket_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);

    if(socket_fd == -1) {
        printf("Failed to create socket\n");
        return -1;
    }

    struct sockaddr_un saddr = { 0 };
    saddr.sun_family = AF_UNIX;
    strncpy(saddr.sun_path, SOCKET_NAME, sizeof(saddr.sun_path) - 1);

    ret = bind(socket_fd, (const sockaddr*) &saddr, sizeof(sockaddr_un));
    if(ret == -1) {
        printf("Failed to bind socket\n");
        return -1;
    }

    ret = listen(socket_fd, 0);
    if(ret == -1) {
        printf("Failed to listen on socket\n");
        return -1;
    }

    printf("Started socket %s\n", SOCKET_NAME);

    return socket_fd;
}

int32_t c_socket_accept(int32_t socket_fd) {
    int32_t client_fd;

    client_fd = accept(socket_fd, NULL, NULL);
    if(client_fd == -1) {
        // printf("No connection to accept\n");
    } else {
        printf("Accepted remote connection\n");
    }

    return client_fd;
}

uint32_t c_socket_process(int32_t fd, uint8_t tdo) {
    int32_t ret;
    char buf, val;

    ret = read(fd, &buf, 1);
    if(ret == -1) {
        // printf("Failed to read from socket\n");
        return -1;
    }

    //nothing read from socket
    if(ret == 0) return 0;

    /* write tck tms tdi
    * reset trst srst
    */
    switch(buf) {
        case 'B': // - Blink on
        {
            break;
        }
        case 'b': // - Blink off
        {
            break;
        }
        case 'R': // - Read request
        {
            val = tdo == 1 ? '1' : '0';
            ret = write(fd, &val, 1);
            if (ret == -1)
                printf("Failed to respond to OpenOCD via socket\n");
            break;
        }
        case 'Q': // - Quit request
        {
            printf("OpenOCD closed remote\n");
            close(fd);
            ret = -2;
            break;
        }
        case '0': // - Write 0 0 0
        case '1': // - Write 0 0 1
        case '2': // - Write 0 1 0
        case '3': // - Write 0 1 1
        case '4': // - Write 1 0 0
        case '5': // - Write 1 0 1
        case '6': // - Write 1 1 0
        case '7': // - Write 1 1 1
        {
            ret = buf - '0';
            break;
        }
        case 'r': // - Reset 0 0
        {
            break;
        }
        case 's': // - Reset 0 1
        {
            break;
        }
        case 't': // - Reset 1 0
        {
            break;
        }
        case 'u': // - Reset 1 1
        {
            break;
        }
        case 'O': // - SWDIO drive 1
        case 'o': // - SWDIO drive 0
        case 'c': // - SWDIO read request
        case 'd': // - SWD write 0 0
        case 'e': // - SWD write 0 1
        case 'f': // - SWD write 1 0
        case 'g': // - SWD write 1 1
        default: 
        {
            printf("Received unsupported OOCD bitbang command %c=%0d\n", buf, (int) buf);
        }
    }

    return ret;
}

#ifdef __cplusplus
}
#endif