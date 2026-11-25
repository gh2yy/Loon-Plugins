/*
 * Taobao-loon.js（淘宝精简版自托管脚本）
 * 本体为可莉的 Taobao_remove_ads.js，原样收录、未改逻辑；原文件头注明其引用自 RuCu6 的 myBlockAds.js。
 * 原始出处：https://kelee.one/Resource/JavaScript/Taobao/Taobao_remove_ads.js
 * 精简版说明：仅供「淘宝（精简版）」插件的开屏/弹窗两条响应脚本钩子使用，改为自托管，不再引用 kelee.one。
 * 2026-11-18 补 acs.m.taobao.com 网关覆盖（开屏配置走主网关时原钩子不触发）。
 * 2026-11-25 防御性加固（开屏分支遍历全部 containers/bizData 键中和）。
 */

/*
脚本引用https://raw.githubusercontent.com/RuCu6/QuanX/main/Scripts/myBlockAds.js
*/
// 2024-01-12 09:10

const url = $request.url;
const isResp = typeof $response !== "undefined";
let body = $response.body;

switch (isResp) {
  // 淘宝-开屏视频广告
  case /^https:\/\/(?:guide-acs|acs)\.m\.taobao\.com\/gw\/mtop\.taobao\.cloudvideo\.video\.query/.test(url):
    try {
      let obj = JSON.parse(body);
      if (obj?.data?.duration) {
        obj.data.duration = "0";
      }
      if (obj?.data?.resources?.length > 0) {
        obj.data.resources = [];
      }
      if (obj?.data?.caches?.length > 0) {
        obj.data.caches = [];
      }
      if (obj?.data?.respTimeInMs) {
        obj.data.respTimeInMs = "3818332800000";
      }
      body = JSON.stringify(obj);
    } catch (err) {
      console.log(`淘宝-开屏视频广告, 出现异常: ` + err);
    }
    break;
  // 淘宝-开屏图片广告
  case /^https:\/\/(?:guide-acs|acs)\.m\.taobao\.com\/gw\/mtop\.taobao\.wireless\.home\.splash\.awesome\.get/.test(url):
    try {
      let obj = JSON.parse(body);
      if (obj?.data?.containers?.splash_home_base) {
        let splash = obj.data.containers.splash_home_base;
        if (splash?.base?.sections?.length > 0) {
          for (let items of splash.base.sections) {
            if ("taobao-splash" in items.bizData) {
              if (items?.bizData?.["taobao-splash"]?.data?.length > 0) {
                for (let item of items.bizData["taobao-splash"].data) {
                  item.waitTime = "0";
                  item.times = "0";
                  item.hotStart = "false";
                  item.haveVoice = "false";
                  item.hideTBLogo = "false";
                  item.enable4G = "false";
                  item.coldStart = "false";
                  item.waitTime = "0";
                  item.startTime = "3818332800000";
                  item.endTime = "3818419199000";
                  item.gmtStart = "2090-12-31 00:00:00";
                  item.gmtEnd = "2090-12-31 23:59:59";
                  item.gmtStartMs = "3818332800000";
                  item.gmtEndMs = "3818419199000";
                  if (item?.imgUrl) {
                    item.imgUrl = "";
                  }
                  if (item?.videoUrl) {
                    item.videoUrl = "";
                  }
                }
              }
            }
          }
        }
      }
      // 防御性加固（2026-11-25）：遍历全部 containers / bizData 键，
      // 凡带 hotStart 或 coldStart 的项按同样方式中和，兜住容器/键名变更；
      // 结构缺层或异形时安全跳过，不带这两属性的项一律不碰。
      {
        const hardenSplashItem = (hItem) => {
          if (!hItem || typeof hItem !== "object") return;
          if (!("hotStart" in hItem) && !("coldStart" in hItem)) return;
          hItem.waitTime = "0";
          hItem.times = "0";
          hItem.hotStart = "false";
          hItem.haveVoice = "false";
          hItem.hideTBLogo = "false";
          hItem.enable4G = "false";
          hItem.coldStart = "false";
          hItem.startTime = "3818332800000";
          hItem.endTime = "3818419199000";
          hItem.gmtStart = "2090-12-31 00:00:00";
          hItem.gmtEnd = "2090-12-31 23:59:59";
          hItem.gmtStartMs = "3818332800000";
          hItem.gmtEndMs = "3818419199000";
          if (hItem?.imgUrl) {
            hItem.imgUrl = "";
          }
          if (hItem?.videoUrl) {
            hItem.videoUrl = "";
          }
        };
        const allContainers = obj?.data?.containers;
        if (allContainers && typeof allContainers === "object") {
          for (const hContainer of Object.values(allContainers)) {
            const hSections = hContainer?.base?.sections;
            if (!Array.isArray(hSections)) continue;
            for (const hSection of hSections) {
              const hBizData = hSection?.bizData;
              if (!hBizData || typeof hBizData !== "object") continue;
              for (const hValue of Object.values(hBizData)) {
                if (Array.isArray(hValue)) {
                  for (const hItem of hValue) hardenSplashItem(hItem);
                } else if (Array.isArray(hValue?.data)) {
                  for (const hItem of hValue.data) hardenSplashItem(hItem);
                }
              }
            }
          }
        }
      }
      body = JSON.stringify(obj);
    } catch (err) {
      console.log(`淘宝-开屏图片广告, 出现异常: ` + err);
    }
    break;
  // 淘宝-开屏活动
  case /^https:\/\/poplayer\.template\.alibaba\.com\/\w+\.json/.test(url):
    try {
      let obj = JSON.parse(body);
      if (obj?.res?.images?.length > 0) {
        obj.res.images = [];
      }
      if (obj?.res?.videos?.length > 0) {
        obj.res.videos = [];
      }
      if (obj?.enable) {
        obj.enable = false;
      }
      if (obj?.mainRes?.images?.length > 0) {
        obj.mainRes.images = [];
      }
      body = JSON.stringify(obj);
    } catch (err) {
      console.log(`淘宝-开屏活动, 出现异常: ` + err);
    }
    break;
  default:
    $done({});
}

$done({ body });
