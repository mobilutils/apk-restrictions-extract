#
# 20260607 few info on those .properties files

each .properties file represents a device,
you can generate one from your device by leveraging this :
=> git@github.com:mobilutils/android-gather-device-properties-via-adb.git

If you are not on mac I have an android app which I didn't sync that can be leveraged, ask me for it I'll publish it (gladly)

by the way each line shall contain 37Lines, to verify it is the case
run this after your generated file :
cat profiles/20260607_SM-T505.properties | cut -d '=' -f 1| grep '^[^#]'

Lazy ay ?
cat "$(ls -t|head -n 1)"| grep '^[^#]'|wc -l

usefull to quickly list fields :
cat "$(ls -t|head -n 1)"| cut -d '=' -f 1| wc -l