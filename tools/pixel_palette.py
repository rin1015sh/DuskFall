# 도트 화면 팔레트 만들기(scenes/battle/pixel_view.gd가 쓰는 assets/pixel/palette.png).
# 게임 화면 캡처(맵마다 --pixel=0 --shot=...)와 assets/ 그림의 색을 Oklab에서 k-평균으로 모은 대표 색
# + 어두운 회색 단계 + 강조 색상환(주문·표시) + 탁한 색 + 피부·머리 색 + 바탕색. 가로 한 줄 PNG(최대 128색).
# 사용: python3 tools/pixel_palette.py <프로젝트 경로> <k-평균 수, 72> <출력 png>  (캡처 폴더는 환경 변수 PAL_SHOTS)
# 필요: numpy, Pillow
import numpy as np, glob, random, sys, os
from PIL import Image
random.seed(1); np.random.seed(1)
def to_lin(c): return np.where(c<=0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def oklab(rgb):
    l=to_lin(rgb)
    M1=np.array([[0.4122214708,0.5363325363,0.0514459929],[0.2119034982,0.6806995451,0.1073969566],[0.0883024619,0.2817188376,0.6299787005]])
    M2=np.array([[0.2104542553,0.7936177850,-0.0040720468],[1.9779984951,-2.4285922050,0.4505937099],[0.0259040371,0.7827717662,-0.8086757660]])
    lms=np.cbrt(l@M1.T); return lms@M2.T
px=[]
for f in glob.glob(os.environ.get('PAL_SHOTS', '/tmp/claude-0/pal') + '/*.png'):
    a=np.asarray(Image.open(f).convert('RGB').crop((100,40,1060,520)),dtype=np.float64)/255
    px.append(a.reshape(-1,3)[::3])
files=glob.glob(sys.argv[1]+'/assets/**/*.png',recursive=True)
random.shuffle(files)
for f in files[:600]:
    try:
        a=np.asarray(Image.open(f).convert('RGBA'),dtype=np.float64)/255
    except Exception: continue
    a=a.reshape(-1,4); a=a[a[:,3]>0.6][:,:3]
    if len(a): px.append(a[::max(1,len(a)//1500)])
P=np.concatenate(px); print(len(P))
L=oklab(P)
keep=L[:,0]>0.22
P=P[keep];L=L[keep]
K=int(sys.argv[2])
# 색 히스토그램(Oklab 칸) — 드물지만 다른 색(흙·물·피부)도 대표를 갖게 개수^0.4로 무게
q=np.round(L/np.array([0.02,0.012,0.012])).astype(np.int64)
keys,inv,cnt=np.unique(q,axis=0,return_inverse=True,return_counts=True)
inv=inv.ravel()
U=np.zeros((len(keys),3)); np.add.at(U,inv,L); U/=cnt[:,None]
R=np.zeros((len(keys),3)); np.add.at(R,inv,P); R/=cnt[:,None]
w=cnt**0.4
C=U[np.random.choice(len(U),K,replace=False,p=w/w.sum())]
for it in range(60):
    d=((U[:,None,:]-C[None,:,:])**2).sum(-1); idx=d.argmin(1)
    for k in range(K):
        m=idx==k
        if m.any(): C[k]=(U[m]*w[m,None]).sum(0)/w[m].sum()
out=[]
for k in range(K):
    m=idx==k
    if m.any(): out.append((R[m]*(cnt[m,None])).sum(0)/cnt[m].sum())
out.append(np.array([0x0c,0x0b,0x0e])/255)  # 바탕
def from_lab(lab):
    M2i=np.linalg.inv(np.array([[0.2104542553,0.7936177850,-0.0040720468],[1.9779984951,-2.4285922050,0.4505937099],[0.0259040371,0.7827717662,-0.8086757660]]))
    M1i=np.linalg.inv(np.array([[0.4122214708,0.5363325363,0.0514459929],[0.2119034982,0.6806995451,0.1073969566],[0.0883024619,0.2817188376,0.6299787005]]))
    l=(lab@M2i.T)**3@M1i.T
    return np.where(l<=0.0031308, 12.92*l, 1.055*np.clip(l,0,None)**(1/2.4)-0.055)
for Lv in (0.08,0.13,0.18,0.24):  # 어두운 회색 단계(약간 차가운)
    out.append(np.clip(from_lab(np.array([Lv,-0.003,-0.008])),0,1))
import math
for h in range(10):
    ang=2*math.pi*h/10+0.5
    for Lv,ch in ((0.42,0.10),(0.65,0.14)):
        c=from_lab(np.array([Lv,ch*math.cos(ang),ch*math.sin(ang)]))
        out.append(np.clip(c,0,1))
for h in range(10):  # 탁한 색(색이 살짝 도는 회색 — 강철·옷감)
    ang=2*math.pi*h/10+0.5
    for Lv in (0.5,0.72):
        out.append(np.clip(from_lab(np.array([Lv,0.045*math.cos(ang),0.045*math.sin(ang)])),0,1))
for Lv,ch in ((0.40,0.06),(0.52,0.07),(0.64,0.075),(0.75,0.065),(0.85,0.05)):  # 피부·머리(주황 쪽 색상)
    ang=math.radians(60)
    out.append(np.clip(from_lab(np.array([Lv,ch*math.cos(ang),ch*math.sin(ang)])),0,1))
out.append(np.array([0.96,0.95,0.92]))
out.sort(key=lambda c: oklab(np.array(c))[0])
img=Image.fromarray((np.array(out)[None,:,:]*255).round().astype(np.uint8))
img.save(sys.argv[3]); print(len(out))
