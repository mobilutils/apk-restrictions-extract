![lalinea book](lalineabook.jpg)
this persona is "Mr. Linea" created by Italian cartoonist Osvaldo Cavandoli ~1970.

# apk-restrictions-extract

a project to easily keep track of MDM restrictions belonging to a specific android app, (usualy [app_restrictions.xml](https://developer.android.com/work/managed-configurations))


Useful to monitor specific app MDM restructions evolution of an app,
this project 
- Downloads the latest APK of the app you are interested in, 
- decompiles it via `apktool`, 
- produces a consolidated CSV/JSON of all available MDM policies.

/!\ If you intend to use it as is, it's fine to test quickly, but you MUST really consider running a dispenser aside, if you want me to I can add a bash script to install and launch one in a subfolder.

## Install dependencies

### Nux (debi/ubuntu)

```bash
apt update && apt upgrade -y && apt-get install apktool python3
#pip install google-play-scraper packaging gplaydl
```

### MacOSx

we need `apktool`
to install it via brew :
```bash
brew upadte && brew upgrade && brew install apktool python3

#pip3 install google-play-scraper packaging gplaydl
```

### Common Nux/MacOsx
```bash

python3 -m venv mvenv
source mvenv/bin/activate

#while waiting for author of gplaydl to include my PR (https://github.com/rehmatworks/gplaydl/pull/48)
pip install google-play-scraper

cd dependency
./dl-modified-gplaydl.sh
cd -
```

## Usage

### Automated (recommended)

`main.sh` handles the full workflow: download the latest APK, extract it, and generate the restriction reports.

```bash
./main.sh
```

### Output

After a successful run, folder `Playstore-Downloads` is created, 
as well as a subfolder with name "<PACKAGE_NAME>_<VERSION>" (e.g: `com.samsung.android.knox.kpu_1.5.64 (26.05)`), 
it contains:

- `app_restrictions.xml` — raw restriction definitions from the APK
- `strings.xml` — resolved string resources
- `app_restrictions_consolidated.json` — structured JSON of all restrictions
- `app_restrictions_consolidated.csv` — tabular CSV with columns: key, title, default_value, type, description


### Cron

the whole idea is to run it daily and sync flat files listed above to a github directory.

```bash
# Run every 2 days at 21:42
42 21 */2 * * (cd /path/to/apk-restrictions-extract && /usr/bin/bash ./main.sh --package-name "com.samsung.android.knox.kpu" --device-profile ./myprofiles/20260606_Samsung_A346B.properties --dispenser "http://192.168.1.42:3000/api/auth")
```

### Kudos
- [Aurora OSS](https://gitlab.com/AuroraOSS/) 
   Kudos to the creators ! Amazing ecosystem, legit, sage, easy to use.

- [gplaydl](https://github.com/rehmatworks/gplaydl)
   Thanks to [gplaydl](https://github.com/rehmatworks/gplaydl) creator [Rehmat Alam](https://github.com/rehmatworks).
   I am using a slight variant that allow to select a specific profile (ours under profiles)


### Monitor logs

```bash
tail -f ~/logs/logs.txt
```
