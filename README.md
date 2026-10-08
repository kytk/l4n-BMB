# Lin4Neuro - BMB (Brain/MINDS Beyond) Docker Container

English | [日本語](#日本語)

---

## English

`kytk/l4n-bmb` is a Docker container for processing the Brain/MINDS Beyond (BMB, "International Brain") dataset with the Human Connectome Project (HCP) Pipelines. It is built on [`kytk/l4n-hcppipelines`](https://github.com/kytk/l4n-HCPpipelines) and adds the tools for BMB: scripts that turn a BMB BIDS session into HCP Pipelines input and run each pipeline step, and RIKEN-BCIL's QC tools.

### Included Software

From the base image `kytk/l4n-hcppipelines` (tag `261004`):

- **HCP Pipelines** v6.0.0
- **FreeSurfer** 6.0.1
- **FSL** 6.0.7.23
- **Connectome Workbench** 2.2.1
- **MSM** (Multimodal Surface Matching) v3.0
- **MATLAB Runtime** R2022b
- **MRIcroGL** v1.2.20220720
- **dcm2niix** v1.0.20260416
- Python 3.12 (venv at `/opt/venv`) with numpy, pandas, matplotlib, seaborn, jupyter, nibabel, nipype, pcntoolkit, and more

Added for BMB:

- **bmb-scripts** (this repository): `bids2hcp.sh`, `bids2seriesinfo.py` and the step scripts `bmb_*.sh` (see [Processing BMB Data](#processing-bmb-data))
- **pyfix model trained on BMB HARP data** (`/usr/local/bmb-models/HARP.pyfix_model`): the ICA-FIX classifier `bmb_icafix.sh` uses
- **[bcil](https://github.com/RIKEN-BCIL/bcil)** (commit `c4a5e52`): QC reports for HCP Pipelines (`hcppipe_qc`, `hcppipe_gqc`), run on the MATLAB Runtime
- **[boldlag](https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning)** v0.2.0: BOLD lag mapping and cleaning (in `/opt/venv`)
- **R** 4.6 with ggplot2 and qcc, **jq** (used by bcil)
- **[cuDIMOT](https://users.fmrib.ox.ac.uk/~moisesf/cudimot/)** NODDI-Watson (built with CUDA 12.8 for RTX 30/40/50 series, in `/usr/local/cudimot`): NODDI on the GPU, with the axial diffusivity at 1.7 × 10⁻³ mm²/s (white matter, the default) or 1.1 × 10⁻³ mm²/s (grey matter). **Needs an NVIDIA GPU**

### Prerequisites

1. Create a shared directory on your host machine
2. Save your FreeSurfer license file (`license.txt`) in this directory
   - You can obtain a FreeSurfer license from: https://surfer.nmr.mgh.harvard.edu/registration.html
3. Put the BMB BIDS data in the shared directory (or mount it separately, see below)

### Starting the Container

1. Open a terminal (Linux/macOS) or PowerShell (Windows)
2. Navigate to your shared directory:

```bash
cd /path/to/your/shared/directory
```

3. Run the following command to start the container:

The same command works on Linux, macOS and Windows (`--privileged` is not needed):

```bash
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

**Windows:** put the shared folder on an **NTFS** drive. exFAT and FAT32 cannot store Linux file ownership, so the `brain` user inside the container cannot write to it. On macOS, exFAT drives work as they are.

### Accessing the Desktop Environment

Open your web browser and navigate to:

```
http://127.0.0.1:6080/vnc.html
```

You will see the Lin4Neuro desktop environment with XFCE4 (password: `lin4neuro`).

### Accessing from a Terminal

The container runs the desktop in the foreground, so `docker run -it` does not give you a shell. Start the container as above, then open a shell in it from a terminal on the host:

```bash
docker exec -it -u brain -w /home/brain l4n-bmb bash
```

- `-u brain`: log in as the `brain` user. Without it you are `root`, and files you create in `share/` will be owned by `root`
- `-w /home/brain`: start in the home directory (`-w` = working directory)
- FSL, FreeSurfer, HCP Pipelines and the BMB scripts are set up automatically (by `~/.bashrc`)
- You may see `xset: unable to open display ":1"` when you log in. It is harmless
- `exit` leaves the shell; the container keeps running, and you can `docker exec` into it again at any time

To run a single command without opening a shell:

```bash
docker exec -u brain -w /home/brain l4n-bmb bash -ic 'bids2hcp.sh ...'
```

If you do not need the desktop at all, you can start the container directly in a shell. In this case the desktop (noVNC) is not started and the ownership of `share/` is not adjusted:

```bash
docker run -it --rm \
  --shm-size=4g \
  --platform linux/amd64 \
  -u brain -w /home/brain \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest bash
```

### Setting up FreeSurfer License

FreeSurfer 6.0.1 requires the license file to be located at `/usr/local/freesurfer/6.0.1/license.txt`.

**Method 1: Copy from host to container**

```bash
docker cp license.txt l4n-bmb:/usr/local/freesurfer/6.0.1/
```

**Method 2: Copy from shared directory inside the container**

After accessing the container desktop, open a terminal and run:

```bash
sudo cp /home/brain/share/license.txt /usr/local/freesurfer/6.0.1/
```

### Processing BMB Data

The scripts are in `/usr/local/bmb-scripts` and in the `PATH`. One BIDS session (`sub-<ID>` + `ses-<ID>`) becomes one HCP subject named `<ID>_<session>`, e.g. `sub-9036` + `ses-UHISkyrafHARP001` → `9036_UHISkyrafHARP001`.

**Supported sessions:** HARP and CRHD (T1w + T2w + spin-echo field maps). SRPB-type sessions (no T2w, GRE field map) are refused.

#### 1. BIDS → HCP Pipelines input (`bids2hcp.sh`)

```bash
bids2hcp.sh -s sub-9036 -e ses-UHISkyrafHARP001 -b ~/share/bids -o ~/share/hcp
```

| Option | Meaning |
|---|---|
| `-s` | subject (`sub-` prefix optional) |
| `-e` | session (`ses-` prefix optional) |
| `-b` | BIDS root directory (contains `sub-*/`) |
| `-o` | HCP StudyFolder; `<StudyFolder>/<Subject>/RawData` is created |
| `-n` | dry run: print the mapping and `hcppipe_conf.txt`, write nothing |
| `-l` | symlink the BIDS files instead of copying them (the BIDS path must be the same inside the container) |
| `-f` | remove an existing `RawData` first |

This writes `<StudyFolder>/<Subject>/RawData/`:

- the images, renamed: `T1w_MPR_1`, `T2w_SPC_1`, `SEField_<k>_AP/PA`, `BOLD_REST_<run>_<AP|PA>` (+ `_SBRef`), `DWI_dir<N>_<AP|PA>` (+ `.bval`, `.bvec`, `_SBRef`)
- `hcppipe_conf.txt`: the inputs and scan parameters (echo spacing, phase encoding direction, the SE field map pair for each run, ...), read by the step scripts and by bcil's QC
- `bids2hcp_map.tsv`: which BIDS file went where, and which were dropped
- `Seriesinfo.csv`, `Studyinfo.csv`: scan parameters of all series in BCILDCMCONVERT's format, rebuilt from the JSON sidecars by `bids2seriesinfo.py`

Selection rules: for CRHD, the prescan-normalized (NORM) T1w/T2w are used; each BOLD run gets the SE field map pair acquired last before it, and a run whose pair is incomplete is dropped; a DWI series with fewer than 2 volumes is dropped. Check `bids2hcp_map.tsv` for what was used.

#### 2. HCP Pipelines (`bmb_*.sh`)

Each step script runs one stage for one subject. They read `hcppipe_conf.txt` and call the standard (human) HCP pipeline directly, with the settings of the upstream human batch scripts in `Examples/Scripts`. Do **not** use `*BatchNHP.sh` for BMB data (NHP = non-human primate), even though they also read `hcppipe_conf.txt`.

```bash
S=~/share/hcp
J=9036_UHISkyrafHARP001

bmb_prefs.sh       $S $J            # PreFreeSurfer (TOPUP with the SE field maps)
bmb_fs.sh          $S $J            # FreeSurfer
bmb_postfs.sh      $S $J            # PostFreeSurfer
bmb_fmrivolume.sh  $S $J [fMRIName] # fMRIVolume (all runs, or one run)
bmb_fmrisurface.sh $S $J [fMRIName] # fMRISurface
bmb_icafix.sh      $S $J            # multi-run ICA-FIX (pyfix, BMB HARP model) over all runs
bmb_diffusion.sh   $S $J [--gpu]    # DiffusionPreprocessing (eddy_cpu, or eddy_cuda with --gpu)
```

- Run them in this order. `bmb_diffusion.sh` needs PostFreeSurfer; `bmb_icafix.sh` needs fMRIVolume and fMRISurface of all runs.
- `BMB_DRYRUN=1 bmb_prefs.sh $S $J` prints the pipeline command without running it.
- `bmb_diffusion.sh` sets `--combine-data-flag` from `hcppipe_conf.txt`: 2 when the AP and PA series do not share a gradient table (HARP), 1 otherwise.
- `--gpu` needs a GPU in the container (see [Using an NVIDIA GPU](#using-an-nvidia-gpu)).

#### 3. QC (bcil)

```bash
hcppipe_qc $S $J -s -d -f       # structural, diffusion, functional QC of one subject
hcppipe_gqc <Group> <Protocol> <Subj1>@<Subj2> ...   # group QC
```

`hcppipe_qc -f` needs the ICA-FIX output. Run a command without arguments to see its options. bcil runs on the MATLAB Runtime (`MATLAB_MODE=runtime`); no MATLAB license is needed.

#### 4. NODDI (cuDIMOT, GPU only)

After `bmb_diffusion.sh`, `T1w/Diffusion/` has what cuDIMOT expects (`data`, `nodif_brain_mask`, `bvals`, `bvecs`):

```bash
Pipeline_NODDI_Watson.sh $S/$J/T1w/Diffusion           # axial diffusivity 1.7e-3 mm²/s (white matter)
Pipeline_NODDI_Watson_Dpar1p1.sh $S/$J/T1w/Diffusion   # axial diffusivity 1.1e-3 mm²/s (grey matter)
```

The results go to `$S/$J/T1w/Diffusion.NODDI_Watson/` and `$S/$J/T1w/Diffusion.NODDI_Watson_Dpar1p1/` (`mean_fintra` = neurite density, `OD` = orientation dispersion index, `mean_fiso`, `mean_kappa`, `dyads1`). The axial (intrinsic parallel) diffusivity is fixed when the model is compiled, so the two are separate programs; nothing else differs between them. The container must be started with the GPU (see [Using an NVIDIA GPU](#using-an-nvidia-gpu)); there is no CPU version. The binaries are built with CUDA 12.8 for RTX 30, 40 and 50 series GPUs (sm_86, sm_89, sm_120); the host needs only the NVIDIA driver, not CUDA. How they are built: [build_cudimot.md](build_cudimot.md) (Japanese).

### Custom Resolution

You can specify a custom resolution when starting the container by setting the `RESOLUTION` environment variable:

```bash
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -e RESOLUTION=1600x900x24 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

Default resolution: 1920x1080x24. The value must be `WIDTHxHEIGHTxDEPTH` (depth 8, 16, 24 or 32); anything else falls back to the default (see `docker logs`).

### Using an NVIDIA GPU

The FSL CUDA programs (`eddy_cuda`, `bedpostx_gpu`, `xfibres_gpu`, `probtrackx2_gpu`, `mmorf_cuda`) and cuDIMOT are included. To run them on the GPU, the host needs:

- **Linux:** the NVIDIA driver and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). After installing the toolkit, run:
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  ```
- **Windows:** the NVIDIA driver for Windows and Docker Desktop with the WSL2 backend (no extra toolkit needed)
- **macOS:** not supported (no NVIDIA GPU)

Add `--gpus all` and `-e NVIDIA_DRIVER_CAPABILITIES=compute,utility` when starting the container:

```bash
docker run \
  --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

`utility` makes `nvidia-smi` available in the container. FSL's `eddy` and `find_cuda_exe` use it to decide whether to run the CUDA version, so do not leave it out.

Check inside the container:

```bash
nvidia-smi                          # the GPU is listed
find_cuda_exe eddy_cuda eddy_cpu    # prints /usr/local/fsl/bin/eddy_cuda
```

Then run `bmb_diffusion.sh <StudyFolder> <Subject> --gpu`, or cuDIMOT.

### Container Management

**Stop the container:**
```bash
docker stop l4n-bmb
```

**Start the container again:**
```bash
docker start l4n-bmb
```

**Remove the container:**
```bash
docker rm -f l4n-bmb
```

### Building the Image

The image is built from the `Dockerfile` in this repository with BuildKit (the default since Docker 23). Everything it needs is in the repository; the base image `kytk/l4n-hcppipelines` (the tag in `BASE_TAG`) is pulled from Docker Hub, and bcil, boldlag, cuDIMOT and CUDA are downloaded during the build. No GPU is needed to build.

```bash
git clone https://github.com/kytk/l4n-BMB.git
cd l4n-BMB
docker build --progress=plain -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
```

To build on another tag of the base image, change `ARG BASE_TAG=...` in the `Dockerfile`. Keeping the tag in the `Dockerfile` records which base each version of this repository is built on.

**Using an Ubuntu mirror (optional):** apt downloads from `archive.ubuntu.com` by default. A nearby mirror can be given with `UBUNTU_MIRROR`:

```bash
docker build --progress=plain \
  --build-arg UBUNTU_MIRROR=https://ftp.riken.jp/Linux/ubuntu \
  -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
```

- `https://` is recommended. On some networks (e.g. behind a caching proxy) HTTP downloads come back broken and apt stops with "Hash Sum mismatch"
- The mirror is used only during the build; the image's `/etc/apt/sources.list` still points to `archive.ubuntu.com`
- `security.ubuntu.com` is not replaced
- Changing the value rebuilds the stages that use apt, so keep using the same mirror

### Notes

- This Docker image is provided for research and educational purposes only
- Please comply with the license terms of all included software packages
- FreeSurfer requires registration and a valid license
- Container runs with user `brain` (password: `lin4neuro`)
- The shared directory is mounted at `/home/brain/share` inside the container
- The base image's scripts for the HCP example data (`~/share/HCPpipelines_ExampleData`) are also available; see [l4n-HCPpipelines](https://github.com/kytk/l4n-HCPpipelines)

### Support

For issues and questions, please visit:
- GitHub Issues: https://github.com/kytk/l4n-BMB/issues
- Lin4Neuro website: https://www.nemotos.net

---

## 日本語

`kytk/l4n-bmb` は、国際脳（Brain/MINDS Beyond、BMB）のデータを Human Connectome Project (HCP) Pipelines で処理するための Docker コンテナです。[`kytk/l4n-hcppipelines`](https://github.com/kytk/l4n-HCPpipelines) を土台にして、BMB 用のツールを追加しています。BMB の BIDS データを HCP Pipelines の入力に変換して各ステップを実行するスクリプトと、理研 BCIL の QC ツールです。

### 含まれるソフトウェア

土台のイメージ `kytk/l4n-hcppipelines`（タグ `261004`）から：

- **HCP Pipelines** v6.0.0
- **FreeSurfer** 6.0.1
- **FSL** 6.0.7.23
- **Connectome Workbench** 2.2.1
- **MSM** (Multimodal Surface Matching) v3.0
- **MATLAB Runtime** R2022b
- **MRIcroGL** v1.2.20220720
- **dcm2niix** v1.0.20260416
- Python 3.12 (venv: `/opt/venv`)。numpy, pandas, matplotlib, seaborn, jupyter, nibabel, nipype, pcntoolkit など

BMB 用に追加したもの：

- **bmb-scripts**（このリポジトリ）: `bids2hcp.sh`、`bids2seriesinfo.py`、ステップごとのスクリプト `bmb_*.sh`（[BMB データの処理](#bmb-データの処理) を参照）
- **BMB HARP のデータで学習した pyfix のモデル**（`/usr/local/bmb-models/HARP.pyfix_model`）: `bmb_icafix.sh` が ICA-FIX の分類に使います
- **[bcil](https://github.com/RIKEN-BCIL/bcil)**（コミット `c4a5e52`）: HCP Pipelines の QC レポート（`hcppipe_qc`、`hcppipe_gqc`）。MATLAB Runtime で動きます
- **[boldlag](https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning)** v0.2.0: BOLD lag mapping と cleaning（`/opt/venv` に導入）
- **R** 4.6（ggplot2、qcc）、**jq**（bcil が使います）
- **[cuDIMOT](https://users.fmrib.ox.ac.uk/~moisesf/cudimot/)** NODDI-Watson（RTX 30/40/50 系向けに CUDA 12.8 でビルド。`/usr/local/cudimot`）: GPU で NODDI を推定します。axial diffusivity が 1.7 × 10⁻³ mm²/s（白質用、既定）の版と 1.1 × 10⁻³ mm²/s（灰白質用）の版があります。**NVIDIA GPU が必要です**

### 事前準備

1. ホストマシン上に共有用のディレクトリを作成してください
2. FreeSurfer のライセンスファイル（`license.txt`）をこのディレクトリに保存してください
   - FreeSurfer のライセンスは以下から取得できます: https://surfer.nmr.mgh.harvard.edu/registration.html
3. BMB の BIDS データを共有ディレクトリに置いてください（別にマウントしてもかまいません）

### コンテナの起動

1. ターミナル（Linux/macOS）または PowerShell（Windows）を開きます
2. 共有ディレクトリに移動します：

```bash
cd 共有ディレクトリのパス
```

3. 以下のコマンドでコンテナを起動します：

Linux、macOS、Windows のいずれも同じコマンドで起動できます（`--privileged` は不要です）：

```bash
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

**Windows:** 共有フォルダは **NTFS** 形式のドライブに置いてください。exFAT や FAT32 は Linux のファイル所有者情報を保存できないため、コンテナ内の `brain` ユーザーが書き込めません。macOS では exFAT のドライブもそのまま使えます。

### デスクトップ環境へのアクセス

Web ブラウザで以下の URL にアクセスしてください：

```
http://127.0.0.1:6080/vnc.html
```

XFCE4 デスクトップ環境の Lin4Neuro が表示されます（パスワード: `lin4neuro`）。

### ターミナルからのアクセス

コンテナはデスクトップをフォアグラウンドで動かしているため、`docker run -it` ではシェルに入れません。上の手順でコンテナを起動したうえで、ホストのターミナルから以下を実行してください：

```bash
docker exec -it -u brain -w /home/brain l4n-bmb bash
```

- `-u brain`: `brain` ユーザーで入ります。付けないと `root` になり、`share/` に作ったファイルの所有者が `root` になります
- `-w /home/brain`: ホームディレクトリから始めます（`-w` は working directory）
- FSL、FreeSurfer、HCP Pipelines、BMB のスクリプトの環境は自動で設定されます（`~/.bashrc` による）
- 入ったときに `xset: unable to open display ":1"` と表示されることがありますが、問題ありません
- `exit` で抜けてもコンテナは動き続けます。何度でも `docker exec` で入り直せます

シェルに入らずにコマンドを 1 つだけ実行する場合：

```bash
docker exec -u brain -w /home/brain l4n-bmb bash -ic 'bids2hcp.sh ...'
```

デスクトップがまったく不要なら、コンテナを最初からシェルで起動することもできます。この場合、デスクトップ（noVNC）は起動せず、`share/` の所有者の調整も行われません：

```bash
docker run -it --rm \
  --shm-size=4g \
  --platform linux/amd64 \
  -u brain -w /home/brain \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest bash
```

### FreeSurfer ライセンスの設定

FreeSurfer 6.0.1 は、ライセンスファイルが `/usr/local/freesurfer/6.0.1/license.txt` に配置されている必要があります。

**方法1: ホストからコンテナにコピー**

```bash
docker cp license.txt l4n-bmb:/usr/local/freesurfer/6.0.1/
```

**方法2: コンテナ内の共有ディレクトリからコピー**

コンテナのデスクトップにアクセスした後、ターミナルを開いて以下を実行：

```bash
sudo cp /home/brain/share/license.txt /usr/local/freesurfer/6.0.1/
```

### BMB データの処理

スクリプトは `/usr/local/bmb-scripts` にあり、`PATH` が通っています。BIDS の 1 セッション（`sub-<ID>` + `ses-<ID>`）を、1 つの HCP の被験者 `<ID>_<セッション>` として扱います。例: `sub-9036` + `ses-UHISkyrafHARP001` → `9036_UHISkyrafHARP001`。

**対応するセッション:** HARP と CRHD（T1w + T2w + スピンエコーのフィールドマップ）。SRPB 型のセッション（T2w がなく、GRE のフィールドマップ）は受け付けません。

#### 1. BIDS → HCP Pipelines の入力（`bids2hcp.sh`）

```bash
bids2hcp.sh -s sub-9036 -e ses-UHISkyrafHARP001 -b ~/share/bids -o ~/share/hcp
```

| オプション | 意味 |
|---|---|
| `-s` | 被験者（`sub-` は省略可） |
| `-e` | セッション（`ses-` は省略可） |
| `-b` | BIDS のルートディレクトリ（`sub-*/` を含む） |
| `-o` | HCP の StudyFolder。`<StudyFolder>/<Subject>/RawData` が作られます |
| `-n` | 試行: 対応表と `hcppipe_conf.txt` を表示するだけで、何も書きません |
| `-l` | BIDS のファイルをコピーせず symlink にします（コンテナ内でも BIDS のパスが同じに見えている必要があります） |
| `-f` | 既存の `RawData` を先に削除します |

`<StudyFolder>/<Subject>/RawData/` に以下が作られます：

- 名前を付け替えた画像: `T1w_MPR_1`、`T2w_SPC_1`、`SEField_<k>_AP/PA`、`BOLD_REST_<run>_<AP|PA>`（+ `_SBRef`）、`DWI_dir<N>_<AP|PA>`（+ `.bval`、`.bvec`、`_SBRef`）
- `hcppipe_conf.txt`: 入力と撮像パラメータ（echo spacing、位相エンコード方向、run ごとの SE フィールドマップの組など）。ステップスクリプトと bcil の QC が読みます
- `bids2hcp_map.tsv`: どの BIDS ファイルがどこに置かれたか、どれを使わなかったか
- `Seriesinfo.csv`、`Studyinfo.csv`: 全シリーズの撮像パラメータを BCILDCMCONVERT の形式で書いたもの。`bids2seriesinfo.py` が JSON から作ります

選び方: CRHD では prescan normalize した（NORM）T1w/T2w を使います。BOLD の各 run には、その直前に撮られた SE フィールドマップの組を割り当て、組がそろっていない run は使いません。2 volume 未満の DWI は使いません。実際に使われたものは `bids2hcp_map.tsv` で確認してください。

#### 2. HCP Pipelines（`bmb_*.sh`）

ステップスクリプトは、1 人の被験者について 1 つのステージを実行します。`hcppipe_conf.txt` を読み、人用の HCP パイプライン本体を、上流の人用 batch（`Examples/Scripts`）と同じ設定で直接呼びます。`*BatchNHP.sh` も `hcppipe_conf.txt` を読みますが、NHP（ヒト以外の霊長類）用なので、BMB のデータには **使わないでください**。

```bash
S=~/share/hcp
J=9036_UHISkyrafHARP001

bmb_prefs.sh       $S $J            # PreFreeSurfer（SE フィールドマップで TOPUP）
bmb_fs.sh          $S $J            # FreeSurfer
bmb_postfs.sh      $S $J            # PostFreeSurfer
bmb_fmrivolume.sh  $S $J [fMRIName] # fMRIVolume（全 run、または 1 run）
bmb_fmrisurface.sh $S $J [fMRIName] # fMRISurface
bmb_icafix.sh      $S $J            # 全 run を連結した multi-run ICA-FIX（pyfix、BMB HARP のモデル）
bmb_diffusion.sh   $S $J [--gpu]    # DiffusionPreprocessing（eddy_cpu。--gpu で eddy_cuda）
```

- この順に実行してください。`bmb_diffusion.sh` は PostFreeSurfer の後、`bmb_icafix.sh` は全 run の fMRIVolume と fMRISurface の後に実行します。
- `BMB_DRYRUN=1 bmb_prefs.sh $S $J` とすると、パイプラインのコマンドを表示するだけで実行しません。
- `bmb_diffusion.sh` の `--combine-data-flag` は `hcppipe_conf.txt` から取ります。AP と PA で勾配の表が違う場合（HARP）は 2、それ以外は 1 です。
- `--gpu` を使うには、コンテナから GPU が見えている必要があります（[NVIDIA GPU を使う](#nvidia-gpu-を使う) を参照）。

#### 3. QC（bcil）

```bash
hcppipe_qc $S $J -s -d -f       # 1 人の構造・拡散・機能の QC
hcppipe_gqc <Group> <Protocol> <Subj1>@<Subj2> ...   # グループ QC
```

`hcppipe_qc -f` には ICA-FIX の出力が必要です。オプションは、各コマンドを引数なしで実行すると表示されます。bcil は MATLAB Runtime で動くので（`MATLAB_MODE=runtime`）、MATLAB のライセンスは不要です。

#### 4. NODDI（cuDIMOT、GPU のみ）

`bmb_diffusion.sh` の後の `T1w/Diffusion/` には、cuDIMOT が必要とするもの（`data`、`nodif_brain_mask`、`bvals`、`bvecs`）がそろっています：

```bash
Pipeline_NODDI_Watson.sh $S/$J/T1w/Diffusion           # axial diffusivity 1.7e-3 mm²/s（白質用）
Pipeline_NODDI_Watson_Dpar1p1.sh $S/$J/T1w/Diffusion   # axial diffusivity 1.1e-3 mm²/s（灰白質用）
```

結果は `$S/$J/T1w/Diffusion.NODDI_Watson/` と `$S/$J/T1w/Diffusion.NODDI_Watson_Dpar1p1/` に出ます（`mean_fintra` = 神経突起密度、`OD` = 方向分散指数、`mean_fiso`、`mean_kappa`、`dyads1`）。axial diffusivity（軸索内の平行方向の拡散係数）はモデルをコンパイルするときに決まる定数なので、2 つは別のプログラムになっています。違いはこの値だけです。コンテナは GPU を使える状態で起動してください（[NVIDIA GPU を使う](#nvidia-gpu-を使う) を参照）。CPU 版はありません。バイナリは RTX 30、40、50 系（sm_86、sm_89、sm_120）向けに CUDA 12.8 でビルドしています。ホストに要るのは NVIDIA ドライバだけで、CUDA は要りません。ビルドの方法は [build_cudimot.md](build_cudimot.md) にあります。

### カスタム解像度

コンテナ起動時に `RESOLUTION` 環境変数を設定することで、カスタム解像度を指定できます：

```bash
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -e RESOLUTION=1600x900x24 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

デフォルト解像度: 1920x1080x24。値は `幅x高さx色深度`（色深度は 8, 16, 24, 32 のいずれか）の形式で指定してください。それ以外の値の場合はデフォルトが使われます（`docker logs` で確認できます）。

### NVIDIA GPU を使う

FSL の CUDA 版プログラム（`eddy_cuda`、`bedpostx_gpu`、`xfibres_gpu`、`probtrackx2_gpu`、`mmorf_cuda`）と cuDIMOT が入っています。GPU で動かすには、ホスト側に以下が必要です。

- **Linux:** NVIDIA ドライバと [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。Toolkit を入れたあと、以下を実行します：
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  ```
- **Windows:** Windows 用の NVIDIA ドライバと、WSL2 バックエンドの Docker Desktop（Toolkit の追加は不要）
- **macOS:** 非対応（NVIDIA GPU がないため）

コンテナ起動時に `--gpus all` と `-e NVIDIA_DRIVER_CAPABILITIES=compute,utility` を付けます：

```bash
docker run \
  --gpus all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

`utility` を指定すると、コンテナ内で `nvidia-smi` が使えるようになります。FSL の `eddy` や `find_cuda_exe` は `nvidia-smi` を使って CUDA 版を使うかどうかを決めるため、省略しないでください。

コンテナ内での確認：

```bash
nvidia-smi                          # GPU が表示される
find_cuda_exe eddy_cuda eddy_cpu    # /usr/local/fsl/bin/eddy_cuda と表示される
```

そのうえで `bmb_diffusion.sh <StudyFolder> <Subject> --gpu` や cuDIMOT を実行します。

### コンテナ管理

**コンテナの停止:**
```bash
docker stop l4n-bmb
```

**コンテナの再起動:**
```bash
docker start l4n-bmb
```

**コンテナの削除:**
```bash
docker rm -f l4n-bmb
```

### イメージのビルド

イメージは、このリポジトリの `Dockerfile` から BuildKit（Docker 23 以降の既定）でビルドします。必要なものはすべてリポジトリに入っています。土台のイメージ `kytk/l4n-hcppipelines`（`BASE_TAG` のタグ）は Docker Hub から取得し、bcil、boldlag、cuDIMOT、CUDA はビルド中にダウンロードします。ビルドに GPU は要りません。

```bash
git clone https://github.com/kytk/l4n-BMB.git
cd l4n-BMB
docker build --progress=plain -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
```

土台のイメージの別のタグでビルドするときは、`Dockerfile` の `ARG BASE_TAG=...` を書き換えます。タグを `Dockerfile` に書いておくことで、このリポジトリの各版がどの土台でビルドされたかが残ります。

**Ubuntu のミラーを使う（任意）：** apt は既定では `archive.ubuntu.com` から取得します。`UBUNTU_MIRROR` で近くのミラーを指定できます：

```bash
docker build --progress=plain \
  --build-arg UBUNTU_MIRROR=https://ftp.riken.jp/Linux/ubuntu \
  -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
```

- `https://` を推奨します。ネットワークによっては（キャッシュするプロキシの内側など）HTTP で取得したファイルが壊れていて、apt が「Hash Sum mismatch」で止まります
- ミラーを使うのはビルドの間だけです。イメージの `/etc/apt/sources.list` は `archive.ubuntu.com` のままです
- `security.ubuntu.com` は置き換えません
- 値を変えると apt を使うステージがビルドし直しになるので、同じミラーを使い続けてください

### 注意事項

- この Docker イメージは研究および教育目的でのみ提供されています
- 含まれるすべてのソフトウェアパッケージのライセンス条項を遵守してください
- FreeSurfer は登録と有効なライセンスが必要です
- コンテナは `brain` ユーザーで実行されます（パスワード: `lin4neuro`）
- 共有ディレクトリはコンテナ内の `/home/brain/share` にマウントされます
- 土台のイメージにある HCP サンプルデータ用のスクリプト（`~/share/HCPpipelines_ExampleData`）も使えます。[l4n-HCPpipelines](https://github.com/kytk/l4n-HCPpipelines) を参照してください

### サポート

問題や質問については、以下をご覧ください：
- GitHub Issues: https://github.com/kytk/l4n-BMB/issues
- Lin4Neuro ウェブサイト: https://www.nemotos.net

---

## License

This Docker container includes multiple software packages, each with its own license. Please ensure you comply with all applicable licenses:

- FreeSurfer: Requires registration and license agreement
- FSL: Requires registration and license agreement
- HCP Pipelines: Custom license by Washington University
- bcil, boldlag: see their repositories (RIKEN-BCIL)
- cuDIMOT: University of Oxford (FMRIB); built from SPMIC-UoN/cudimot, with the source as built in `/usr/local/cudimot/src`
- CUDA runtime (linked into the cuDIMOT binaries): NVIDIA CUDA Toolkit EULA
- bmb-scripts: MIT License (this repository)
- Other software: Various open-source licenses

**Author:** K. Nemoto
**Date:** 2026-10-05
