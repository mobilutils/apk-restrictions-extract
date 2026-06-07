#run the following commands to get the modified version of gplaydl
git clone -b feat/auth-by-profile https://github.com/mobilutils/gplaydl.git
cd gplaydl
python3 -m venv mvenv
source mvenv/bin/activate
pip3 install .
