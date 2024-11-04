# Manipulating images
**Learn how to maniplate images**

## Disk Expansion
**1. Access Troubleshooting Shell:**

> During the boot-up process, access the troubleshooting shell.
## 2. Disk Resizing:

> Execute the following command to expand your disk using qemu-img:

``qemu-img resize diskname.qcow2 +50G``
> **Use your actual diskname and the size**
## 3. Boot Up:

> Once the disk has been resized, proceed to boot up the system.
## 4. Partition and File System Expansion:

> After booting, follow these steps to expand the partitions:
> Use growpart to extend the partition:

``growpart /dev/sda 1``
> Resize the file system with resize2fs:


``resize2fs /dev/sda1``
