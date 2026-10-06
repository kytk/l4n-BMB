# kytk/l4n-bmb - Lin4Neuro BMB (Brain/MINDS Beyond) Docker Container

[English](#english) | [日本語](#japanese)

---

## English

### Overview
`kytk/l4n-bmb` is a Docker container for processing the Brain/MINDS Beyond (BMB, "International Brain") dataset with the Human Connectome Project (HCP) Pipelines. It is built on [`kytk/l4n-hcppipelines`](https://hub.docker.com/r/kytk/l4n-hcppipelines) (Lin4Neuro, an Ubuntu-based neuroimaging environment with an XFCE4 desktop in the web browser through noVNC) and adds scripts that turn a BMB BIDS session into HCP Pipelines input and run each pipeline step, and RIKEN-BCIL's QC tools.

### Features
- **Complete Desktop Environment**: XFCE4 desktop with web browser access
- **Pre-installed Neuroimaging Software**:
  - HCP Pipelines v6.0.0
  - FreeSurfer 6.0.1
  - FSL 6.0.7.23
  - Connectome Workbench 2.2.1
  - MSM (Multimodal Surface Matching) v3.0
  - MATLAB Runtime R2022b
  - MRIcroGL v1.2.20220720
  - dcm2niix v1.0.20260416
- **Added for BMB**:
  - bmb-scripts: `bids2hcp.sh`, `bids2seriesinfo.py`, step scripts `bmb_*.sh`
  - pyfix model trained on BMB HARP data (used by `bmb_icafix.sh`)
  - [bcil](https://github.com/RIKEN-BCIL/bcil) (`c4a5e52`): HCP Pipelines QC (`hcppipe_qc`, `hcppipe_gqc`) on the MATLAB Runtime
  - [boldlag](https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning) v0.2.0
  - R 4.6 (ggplot2, qcc), jq
  - [cuDIMOT](https://users.fmrib.ox.ac.uk/~moisesf/cudimot/) NODDI-Watson (GPU only; CUDA 12.8 build for RTX 30/40/50 series; axial diffusivity 1.7e-3 or 1.1e-3 mm²/s)
- **Development Tools**: Python 3.12 (venv at `/opt/venv`), Jupyter Notebook, Git
- **Python Packages**: numpy, pandas, matplotlib, seaborn, nibabel, nipype, pcntoolkit, and more
- **Multi-language Support**: English and Japanese fonts/locales

### Quick Start

#### Prerequisites
- Docker installed on your system
- FreeSurfer license file (`license.txt`)
  - You can obtain a FreeSurfer license from: https://surfer.nmr.mgh.harvard.edu/registration.html

#### Basic Usage (GUI Mode)

The same command works on Linux, macOS and Windows:
```bash
# Place your FreeSurfer license.txt in the current directory
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

- `-p 127.0.0.1:6080:6080` makes the desktop reachable only from your own computer (the VNC password is public).
- `--privileged` is not needed on any platform.

#### Shared Folder Format (Windows)
On Windows, the shared folder must be on an **NTFS** drive. exFAT and FAT32 cannot store Linux file ownership, so the `brain` user inside the container cannot write to the folder. If your external drive is exFAT, back up its contents and reformat it as NTFS. On macOS, exFAT drives work as they are.

#### Interactive Shell Mode
```bash
docker run -it \
  --shm-size=4g \
  --platform linux/amd64 \
  -v .:/home/brain/share \
  --name l4n-bmb \
  kytk/l4n-bmb:latest
```

#### Access the Desktop
1. Open your web browser
2. Navigate to `http://127.0.0.1:6080/vnc.html`
3. Enter password: `lin4neuro`

### Environment Modes

#### GUI Mode (Default)
- Starts XFCE4 desktop environment
- Accessible via web browser at `http://127.0.0.1:6080/vnc.html`
- Password: `lin4neuro`

#### Bash Mode
- Provides interactive command-line access
- Start the container with `-it` instead of `-d` (no `-p` needed): a shell as `brain` opens instead of the desktop
- All neuroimaging tools available in PATH
- HCP Pipelines and all dependencies are pre-configured

### Volume Mounts

#### Required: Shared Directory
```bash
-v .:/home/brain/share
```
**Important**: Your FreeSurfer `license.txt` must be in the mounted directory.

#### Optional: Data Directory
```bash
-v /path/to/your/data:/home/brain/data
```

### FreeSurfer License Setup

FreeSurfer 6.0.1 requires the license file to be located at `/usr/local/freesurfer/6.0.1/license.txt`.

#### Method 1: Copy from host to container
```bash
docker cp license.txt l4n-bmb:/usr/local/freesurfer/6.0.1/
```

#### Method 2: Copy from shared directory inside the container
After accessing the container desktop, open a terminal and run:
```bash
sudo cp /home/brain/share/license.txt /usr/local/freesurfer/6.0.1/
```

### Processing BMB Data

One BIDS session becomes one HCP subject `<ID>_<session>` (e.g. `sub-9036` + `ses-UHISkyrafHARP001` → `9036_UHISkyrafHARP001`). HARP and CRHD sessions are supported; SRPB-type sessions (no T2w) are refused. Details: [GitHub README](https://github.com/kytk/l4n-BMB).

```bash
# 1. BIDS -> <StudyFolder>/<Subject>/RawData (images + hcppipe_conf.txt)
#    -n: dry run, -l: symlink instead of copy, -f: overwrite RawData
bids2hcp.sh -s sub-9036 -e ses-UHISkyrafHARP001 -b ~/share/bids -o ~/share/hcp

# 2. HCP Pipelines, one step per script (human pipelines; do not use *BatchNHP.sh)
S=~/share/hcp; J=9036_UHISkyrafHARP001
bmb_prefs.sh $S $J
bmb_fs.sh $S $J
bmb_postfs.sh $S $J
bmb_fmrivolume.sh $S $J
bmb_fmrisurface.sh $S $J
bmb_icafix.sh $S $J
bmb_diffusion.sh $S $J [--gpu]

# 3. QC (bcil)
hcppipe_qc $S $J -s -d -f

# 4. NODDI-Watson (cuDIMOT; GPU only) -> T1w/Diffusion.NODDI_Watson/ (axial diffusivity 1.7e-3 mm²/s, white matter)
Pipeline_NODDI_Watson.sh $S/$J/T1w/Diffusion
#    1.1e-3 mm²/s (grey matter) -> T1w/Diffusion.NODDI_Watson_Dpar1p1/
Pipeline_NODDI_Watson_Dpar1p1.sh $S/$J/T1w/Diffusion
```

`BMB_DRYRUN=1 bmb_<step>.sh ...` prints the pipeline command without running it. `bids2hcp_map.tsv` in RawData records which BIDS files were used or dropped.

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

The FSL CUDA programs (`eddy_cuda`, `bedpostx_gpu`, `xfibres_gpu`, `probtrackx2_gpu`, `mmorf_cuda`) are included. To run them on the GPU, the host needs:

- **Linux:** the NVIDIA driver and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), then `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`
- **Windows:** the NVIDIA driver for Windows and Docker Desktop with the WSL2 backend
- **macOS:** not supported

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

`utility` makes `nvidia-smi` available in the container; FSL's `eddy` and `find_cuda_exe` use it to decide whether to run the CUDA version. Check with `nvidia-smi` and `find_cuda_exe eddy_cuda eddy_cpu` (prints `/usr/local/fsl/bin/eddy_cuda`). Then run `bmb_diffusion.sh <StudyFolder> <Subject> --gpu`.

### Port Mapping
- Port `6080`: noVNC web interface

### Default User
- Username: `brain`
- Password: `lin4neuro`
- Home directory: `/home/brain`

### Software Paths and Environment Variables
- **HCP Pipelines**: `/home/brain/projects/HCPpipelines` (HCPPIPEDIR set in `Examples/Scripts/SetUpHCPPipeline.sh`)
- **FreeSurfer**: `/usr/local/freesurfer/6.0.1` (automatically configured)
- **FSL**: `/usr/local/fsl` (FSLDIR set)
- **Connectome Workbench**: `/usr/local/workbench` (in PATH)
- **MSM**: Available in PATH
- **MATLAB Runtime**: `/usr/local/MATLAB/MCR/R2022b`
- **bmb-scripts**: `/usr/local/bmb-scripts` (in PATH)
- **pyfix model (BMB HARP)**: `/usr/local/bmb-models/HARP.pyfix_model` (used by `bmb_icafix.sh`)
- **bcil**: `/usr/local/bcil` (BCILDIR set, `bin/` in PATH, `MATLAB_MODE=runtime`)
- **cuDIMOT**: `/usr/local/cudimot` (CUDIMOT set, `bin/` in PATH)

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

### Troubleshooting
- If GUI doesn't load, wait 30 seconds for all services to start
- Check container logs: `docker logs l4n-bmb`
- Restart container: `docker restart l4n-bmb`
- Ensure FreeSurfer license is properly installed at `/usr/local/freesurfer/6.0.1/license.txt`

---

## Japanese

### 概要
`kytk/l4n-bmb` は、国際脳（Brain/MINDS Beyond、BMB）のデータを Human Connectome Project (HCP) Pipelines で処理するための Docker コンテナです。[`kytk/l4n-hcppipelines`](https://hub.docker.com/r/kytk/l4n-hcppipelines)（Lin4Neuro。noVNC を通じて Web ブラウザから XFCE4 デスクトップを使える、Ubuntu ベースの神経画像解析環境）を土台に、BMB の BIDS データを HCP Pipelines の入力に変換して各ステップを実行するスクリプトと、理研 BCIL の QC ツールを追加しています。

### 特徴
- **完全なデスクトップ環境**: WebブラウザアクセスでXFCE4デスクトップ
- **事前インストール済み神経画像解析ソフトウェア**:
  - HCP Pipelines v6.0.0
  - FreeSurfer 6.0.1
  - FSL 6.0.7.23
  - Connectome Workbench 2.2.1
  - MSM (Multimodal Surface Matching) v3.0
  - MATLAB Runtime R2022b
  - MRIcroGL v1.2.20220720
  - dcm2niix v1.0.20260416
- **BMB 用に追加**:
  - bmb-scripts: `bids2hcp.sh`、`bids2seriesinfo.py`、ステップごとのスクリプト `bmb_*.sh`
  - BMB HARP のデータで学習した pyfix のモデル（`bmb_icafix.sh` が使用）
  - [bcil](https://github.com/RIKEN-BCIL/bcil)（`c4a5e52`）: HCP Pipelines の QC（`hcppipe_qc`、`hcppipe_gqc`）。MATLAB Runtime で動作
  - [boldlag](https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning) v0.2.0
  - R 4.6（ggplot2、qcc）、jq
  - [cuDIMOT](https://users.fmrib.ox.ac.uk/~moisesf/cudimot/) NODDI-Watson（GPU のみ。RTX 30/40/50 系向けに CUDA 12.8 でビルド。axial diffusivity 1.7e-3 と 1.1e-3 mm²/s の 2 版）
- **開発ツール**: Python 3.12 (venv: `/opt/venv`), Jupyter Notebook, Git
- **Python パッケージ**: numpy, pandas, matplotlib, seaborn, nibabel, nipype, pcntoolkit など
- **多言語サポート**: 英語・日本語フォント/ロケール

### クイックスタート

#### 前提条件
- システムにDockerがインストールされていること
- FreeSurferライセンスファイル（`license.txt`）
  - FreeSurfer のライセンスは以下から取得できます: https://surfer.nmr.mgh.harvard.edu/registration.html

#### 基本使用方法（GUIモード）

Linux、macOS、Windows のいずれも同じコマンドで起動できます:
```bash
# FreeSurferのlicense.txtを現在のディレクトリに配置
docker run \
  --shm-size=4g \
  --platform linux/amd64 \
  --name l4n-bmb \
  -d -p 127.0.0.1:6080:6080 \
  -v .:/home/brain/share \
  kytk/l4n-bmb:latest
```

- `-p 127.0.0.1:6080:6080` とすることで、デスクトップには自分のコンピュータからのみ接続できます（VNC のパスワードは公開されているため）。
- どの OS でも `--privileged` は不要です。

#### 共有フォルダの形式（Windows）
Windows では、共有フォルダは **NTFS** 形式のドライブに置いてください。exFAT や FAT32 は Linux のファイル所有者情報を保存できないため、コンテナ内の `brain` ユーザーが共有フォルダに書き込めません。外付けドライブが exFAT の場合は、中身をバックアップしてから NTFS で再フォーマットしてください。macOS では exFAT のドライブもそのまま使えます。

#### 対話型シェルモード
```bash
docker run -it \
  --shm-size=4g \
  --platform linux/amd64 \
  -v .:/home/brain/share \
  --name l4n-bmb \
  kytk/l4n-bmb:latest
```

#### デスクトップへのアクセス
1. Webブラウザを開く
2. `http://127.0.0.1:6080/vnc.html` にアクセス
3. パスワードを入力: `lin4neuro`

### 環境モード

#### GUIモード（デフォルト）
- XFCE4デスクトップ環境を開始
- Webブラウザから `http://127.0.0.1:6080/vnc.html` でアクセス
- パスワード: `lin4neuro`

#### Bashモード
- 対話型コマンドラインアクセスを提供
- `-d` の代わりに `-it` を付けて起動します（`-p` は不要）。デスクトップの代わりに `brain` ユーザーのシェルが開きます
- すべての神経画像解析ツールがPATHで利用可能
- HCP Pipelines とすべての依存関係が事前設定済み

### ボリュームマウント

#### 必須: 共有ディレクトリ
```bash
-v .:/home/brain/share
```
**重要**: FreeSurferの `license.txt` がマウントされたディレクトリに存在する必要があります。

#### オプション: データディレクトリ
```bash
-v /path/to/your/data:/home/brain/data
```

### FreeSurfer ライセンスの設定

FreeSurfer 6.0.1 は、ライセンスファイルが `/usr/local/freesurfer/6.0.1/license.txt` に配置されている必要があります。

#### 方法1: ホストからコンテナにコピー
```bash
docker cp license.txt l4n-bmb:/usr/local/freesurfer/6.0.1/
```

#### 方法2: コンテナ内の共有ディレクトリからコピー
コンテナのデスクトップにアクセスした後、ターミナルを開いて以下を実行：
```bash
sudo cp /home/brain/share/license.txt /usr/local/freesurfer/6.0.1/
```

### BMB データの処理

BIDS の 1 セッションを、1 つの HCP の被験者 `<ID>_<セッション>` として扱います（例: `sub-9036` + `ses-UHISkyrafHARP001` → `9036_UHISkyrafHARP001`）。HARP と CRHD に対応し、SRPB 型（T2w なし）は受け付けません。詳しくは [GitHub の README](https://github.com/kytk/l4n-BMB) を参照してください。

```bash
# 1. BIDS -> <StudyFolder>/<Subject>/RawData（画像と hcppipe_conf.txt）
#    -n: 試行、-l: コピーせず symlink、-f: RawData を作り直す
bids2hcp.sh -s sub-9036 -e ses-UHISkyrafHARP001 -b ~/share/bids -o ~/share/hcp

# 2. HCP Pipelines。1 スクリプト 1 ステップ（人用のパイプライン。*BatchNHP.sh は使わない）
S=~/share/hcp; J=9036_UHISkyrafHARP001
bmb_prefs.sh $S $J
bmb_fs.sh $S $J
bmb_postfs.sh $S $J
bmb_fmrivolume.sh $S $J
bmb_fmrisurface.sh $S $J
bmb_icafix.sh $S $J
bmb_diffusion.sh $S $J [--gpu]

# 3. QC（bcil）
hcppipe_qc $S $J -s -d -f

# 4. NODDI-Watson（cuDIMOT。GPU のみ）-> T1w/Diffusion.NODDI_Watson/（axial diffusivity 1.7e-3 mm²/s、白質用）
Pipeline_NODDI_Watson.sh $S/$J/T1w/Diffusion
#    1.1e-3 mm²/s（灰白質用）-> T1w/Diffusion.NODDI_Watson_Dpar1p1/
Pipeline_NODDI_Watson_Dpar1p1.sh $S/$J/T1w/Diffusion
```

`BMB_DRYRUN=1 bmb_<ステップ>.sh ...` とすると、パイプラインのコマンドを表示するだけで実行しません。どの BIDS ファイルを使ったか（使わなかったか）は RawData の `bids2hcp_map.tsv` に記録されます。

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

FSL の CUDA 版プログラム（`eddy_cuda`、`bedpostx_gpu`、`xfibres_gpu`、`probtrackx2_gpu`、`mmorf_cuda`）が入っています。GPU で動かすには、ホスト側に以下が必要です。

- **Linux:** NVIDIA ドライバと [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)。入れたあと `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker` を実行
- **Windows:** Windows 用の NVIDIA ドライバと、WSL2 バックエンドの Docker Desktop
- **macOS:** 非対応

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

`utility` を指定すると、コンテナ内で `nvidia-smi` が使えます。FSL の `eddy` や `find_cuda_exe` はこれを使って CUDA 版を使うか決めます。`nvidia-smi` と `find_cuda_exe eddy_cuda eddy_cpu`（`/usr/local/fsl/bin/eddy_cuda` と表示される）で確認できます。そのうえで `bmb_diffusion.sh <StudyFolder> <Subject> --gpu` を実行します。

### ポートマッピング
- ポート `6080`: noVNC Webインターフェース

### デフォルトユーザー
- ユーザー名: `brain`
- パスワード: `lin4neuro`
- ホームディレクトリ: `/home/brain`

### ソフトウェアパスと環境変数
- **HCP Pipelines**: `/home/brain/projects/HCPpipelines` (HCPPIPEDIR は `Examples/Scripts/SetUpHCPPipeline.sh` で設定)
- **FreeSurfer**: `/usr/local/freesurfer/6.0.1` (自動設定)
- **FSL**: `/usr/local/fsl` (FSLDIR設定済み)
- **Connectome Workbench**: `/usr/local/workbench` (PATH設定済み)
- **MSM**: PATH利用可能
- **MATLAB Runtime**: `/usr/local/MATLAB/MCR/R2022b`
- **bmb-scripts**: `/usr/local/bmb-scripts` (in PATH)
- **pyfix model (BMB HARP)**: `/usr/local/bmb-models/HARP.pyfix_model` (used by `bmb_icafix.sh`)
- **bcil**: `/usr/local/bcil` (BCILDIR set, `bin/` in PATH, `MATLAB_MODE=runtime`)
- **cuDIMOT**: `/usr/local/cudimot` (CUDIMOT set, `bin/` in PATH)

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

### トラブルシューティング
- GUIが読み込まれない場合は、すべてのサービスが開始されるまで30秒お待ちください
- コンテナログを確認: `docker logs l4n-bmb`
- コンテナを再起動: `docker restart l4n-bmb`
- FreeSurferライセンスが `/usr/local/freesurfer/6.0.1/license.txt` に正しくインストールされていることを確認してください

---

## Technical Details

### System Requirements
- RAM: 8GB minimum, 16GB+ recommended (for HCP Pipeline processing)
- Disk space: ~31GB for container image
- Supported platforms: Linux (x86_64), macOS (x86_64), Windows with WSL2
- Docker flags required: `--shm-size=4g --platform linux/amd64` (no `--privileged` needed)
- Shared folder on Windows: NTFS drive required (exFAT/FAT32 cannot store Linux file ownership)
- GPU (optional): NVIDIA GPU with the NVIDIA Container Toolkit (Linux) or Docker Desktop + WSL2 (Windows); start with `--gpus all`

### Container Details
- Base image: `kytk/l4n-hcppipelines:261004` (Ubuntu 22.04 LTS)
- Desktop environment: XFCE4
- VNC server: x11vnc
- Web interface: noVNC
- Default user: brain (non-root)
- Default resolution: 1920x1080x24 (customizable via RESOLUTION environment variable)

### Included Software Versions
- HCP Pipelines: v6.0.0
- FreeSurfer: 6.0.1
- FSL: 6.0.7.23
- Connectome Workbench: 2.2.1
- MSM: v3.0
- MATLAB Runtime: R2022b
- MRIcroGL: v1.2.20220720
- dcm2niix: v1.0.20260416
- bcil: `c4a5e52`
- boldlag: v0.2.0
- R: 4.6.1 (ggplot2, qcc from Posit Package Manager, 2026-10-01 snapshot)
- cuDIMOT: NODDI-Watson, built from SPMIC-UoN/cudimot (`5f9e4ff`) with CUDA 12.8 (sm_86, sm_89, sm_120; runtime linked statically). The source as built is in `/usr/local/cudimot/src`

### License
This container includes multiple software packages, each with its own license. Users are responsible for ensuring compliance with all applicable licenses:

- FreeSurfer: Requires registration and license agreement
- FSL: Requires registration and license agreement
- HCP Pipelines: Custom license by Washington University
- bcil, boldlag: see their repositories (RIKEN-BCIL)
- bmb-scripts: MIT License
- cuDIMOT: University of Oxford (FMRIB)
- CUDA runtime (linked into the cuDIMOT binaries): NVIDIA CUDA Toolkit EULA
- Other software: Various open-source licenses

### Support
- Author: K. Nemoto
- GitHub: https://github.com/kytk/l4n-BMB
- Base image: https://hub.docker.com/r/kytk/l4n-hcppipelines
- Lin4Neuro website: https://www.nemotos.net
- Issues: https://github.com/kytk/l4n-BMB/issues

### Version History
- 2026-10-05: base `kytk/l4n-hcppipelines:261004` (wb_view fixed), cuDIMOT NODDI-Watson (GPU only).
- 2026-10-04: bcil `c4a5e52` (group QC summary; ggQC and gridExtra no longer needed).
- 2026-10-03: Initial release on `kytk/l4n-hcppipelines:261003`: bmb-scripts, bcil, boldlag v0.2.0, R.
