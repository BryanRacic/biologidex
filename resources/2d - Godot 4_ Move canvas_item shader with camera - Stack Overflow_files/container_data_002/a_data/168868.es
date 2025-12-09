
                var fireBeacon = function(url) {
            try {
                if(url && url != "null" && url != "undefined"){
                    var timeStamp = new Date().getTime() + "";
                    var beacon = url.replace("[timestamp]", timeStamp);//TODO double check macro.
                    var bImage = new Image();
                    bImage.src = beacon;
                }
            } catch(e){
            }
        }

        
        var encode = function(url) {
            var arr;
            var re_unenc=/\${lp_url}/;
            var re_enc=/\${lp_url_enc_(\d+)}/;
            if (arr=url.match(re_unenc)) {
                url = encode(url.substring(0,arr["index"])) + arr[0] + encode(url.substring(arr["index"] + arr[0].length));
                return url.replace(re_unenc,"${lp_url_enc_1}");
            } else if (arr=url.match(re_enc)) {
                url = encode(url.substring(0,arr["index"])) + arr[0] + encode(url.substring(arr["index"] + arr[0].length));
                return url.replace(re_enc,"\${lp_url_enc_" + (Number(arr[1]) + 1) + "}");
            } else {
                return encodeURIComponent(url);
            }
        }
        

                    var getClickUrl = function(url) {
                                    return "https://stats-creative-tm.everesttech.net/c?cro=true&auth=9745d24658c9ca5ba47ec85bd74452e4&iid=aThYZgAAASxalwA2&exp=311&aid=461755&crid=25971&def=false&dsp=3&dbid=33686707&dsid=6958819&daid=aThYZgAAASxalwA2&dpid=424555874&dadid=617516314&dcid=238262328&dpp=424555874&uid=aThYZgAAASxamAA2&uidt=EVEREST_COOKIE_ID&ua=Mozilla%2F5.0+%28X11%3B+Ubuntu%3B+Linux+x86_64%3B+rv%3A145.0%29+Gecko%2F20100101+Firefox%2F145.0&tid=874&pc=45223&m=515&c=Cincinnati&reg=OH&cty=US&dppf=t&gpf=t&ppf=f&spf=f&cst=DT_TARGETED&pids=992897&sz=300x600&et=1765300326825&redir=" + encode("https://adclick.g.doubleclick.net/pcs/click?xai=AKAOjstfTjAyVWGDwXDR8iok0OAI6jQEBIk41Kp6QFGnWSfWtfu1wdF37cXA4erqEvro3gLPqxgn44MBR2yNYc1BHXWaPW4R8bOd8Z8hltEjQf8oWWmSBh3lsPIGswDbOprBjLPK8B4pVfkAZdWNUxcO4-EyyEOOovCU_GXFvQWQXws-FKI7bbsyt8_4tqwyTwWmBj0r_zLC0WmLgXuI8QeEYnypAWbMzIGAF0xAkqF1pjMqoL_yr4hUGjs2CEVJTZhviDrm-fz5a6hC5JGy9X8trG64DP1UJDNiAVcFANu3tw5B2uDZhkxIOCqU0fnPMFi-BYfzT7Ofb-YX_hR2er9lbwe9BiyPkqq9Yow1YOKeiCnrVNkePdo1WQlTIOsdqVnk0Q8LvNEqOxc8knwK4Hda38S_eJm9J3rBRiPfZjOSZxY5N4rzb1RDJaMwOAxMf9EhkdfJQHGG30ntMpW5Pd4jfEx8vET0svasvkR90_RIjIzRFtSSEck6Twsm_SFk2fIJYXb-w9JZDotImPo6izp7IeRGTPRRD6hztVGqJsrdFAKj6grSieIZUjWXo5dO84spLHCLGbs3Rtdk3UvMPNJUmPfphjnMpL1WDgoYof-pGVLiC_NJAFUzLZ0PecdDPZ29k-eCGFxTaekc16_1b6e5zFJA1902pFHIRIG4Bdrxz3ZX-YuPSLZlMQIFGAxYZ6WPZLEDjpDvvBFlqK7ganeW94uO-EKPZne777Uf5P5rYEKVcXrlYQzVzqiOx4F7wcUpW_unp3F9d7BXxssY2CdzwcweKeXffX_O9ENhuTQr91W-FHXzTxIdbjAEnolo7kc8MWljT3om4DmVx5bKk0_cT49T_2YJ_Mbjj-T8zy5yQHVU2_U0pPiYWSSu1N3zTvvoBi-jn2qDaerHx_ezi5EZvkTPs060Sim1J84dAOvCcyKdw7sMoQMR_edDAYJ-6rIdRU4QmDKcWuCrhtRodN8gVXblTVcnp6LvfjsgggOOi_MWgpqcKFxQuKHv9MOxftCgewLBu8VkcuiLiwKwCaCwoiEHY3hjirMPcqTNGMgkYcGUNRZxjAZ7Zc2xAEU1kdCP9sg_IrddUGOAJKG5GH5DN8gxPtiLvCK9YZxSbpbtMnYPBMhUzXi47lSkDIKgaKgx5kFNS0LtzWqv8Ro8-z29w4AOqmgwvmzPHSjNdhz2T7brf_tHs4xWZ-SNQq-EmULcsoCdnCxIv7SxJ_Y7CGYVEOdmHqiuokCgCIw51i6uGLKBKuAIWYhd6I219cl9JwbAcWOtQSSuHHcG4_eh8MlH4IzArqZvbrc_CInUshIQwN9t1OKv25LtBrMLDjdyoihoWpajbJUDevmy8btAkNWNLClx4uC0qPmMqVX6koP9fzZKw4rMDvJA57DNW6O9MgbxGVfhNWqpstBgAnjJnUv9PTk6RSeLDAV5WQk_FDUDz3Jus9lrz9ACzOI2q0qYNs5zeJx44SgoP5eREhjZ4EN7VeBb-aYTlXl9c7BIaEJPMtT4vNoGoevmGqTPlnf_zOFgxmJhHQKC4TLOTDjd411oQrPZXtw-b7kDvnUrleKz0z1NLzXVFOY8GjgwDVTAkxebviwsA1Rz03uEFF49HfNign7cCbqiLR-lGHKK7_ErQEfOT5oEKKGUIi1bbf__f6GdwfSoJfl41FfLqngPaFH6uxi_cF2-DgSlw3QnoJJTrNpRPhph7j_8WuNY1wMKbKvM25wn6zx1SHZq-RnOMJqDkyf7Rez-zoZT-XQLTtSKRWE7yzbIiWkl65_w17-lEE9s1xSVWA0DxO3_mwT7-WJkXHkrWepxLd9U-NkLpns8vANo6-U-SMWSOXaHGB_h8OMtquA85E5syKHxKH0Ob0JWARi9JHpwESG7mPvxfV56XDZoiKnRUs8cW73RM-QyX0eCGp3MSpPwtfOzIj5qM2BrH0WiCqUAPOHQjhFg0kwf4ci-iGjQxqC_zxxYIe_P5aOZWq07QmMfbt5_saqKXg27NJAWZ_sW8N9PywXdxOvRBJmt03Rox_efGJDuJIK7c0XwVRPfNbM3uGHshdIKYMXJvqs&sai=AMfl-YTp7lx91SHMr6e9S9c7qtxnQEiWnb1dL62p3yF2Q_GHhoGptC8iFJwh8mO6IWKXDY27xsN7Tezr65Gc2bU2aDqlt7o-dtq0GInjenRlr1oRaqdTUuwkivJ8HRItbvnaRtnE_N7cI3MBhnouezH227hveBoYuYL5UELP6LNEDZBJ4S3b7HwrGgplSjhbWgk8k4ZAU1NFNqWwat9xJ9tF_C6CxZ8E1QGeqpe_pLqrPPKOTP7oXGd2n4JdY2K2mz6Xn4A9C-4xDFIut6Da439eCMUwqIfwhRRufA2lEQq9VQ0abi_-AKTKt4-HtQUcYhe_VQrZUeK9ZKNEdbAnkbhlBMbqu0DIILDRRuomdaiUdG52FDYz8ywEd8tVm4L-Vr9JPAMn1_z1uQciIgQXGViWb9cDeRkNRHZiuq_W9S5Ko3cSFglR-OFFTgIL-uOseCi6ZEn52PxlURBu7RAEC7yPe0xrOrRTsLZmFdSI-7ANX-OaSpvD6_X0G6VOHU2khJTDivwwZqJ8ijr-4ku7q_swESRarKuLWEyOvo9fPYQ&sig=Cg0ArKJSzFKTO1omojs-EAE&fbs_aeid=%5Bgw_fbsaeid%5D&urlfix=1&adurl=" + encode(url));
                            }

             var getEngagementUrl = function() {
                 return "https://stats-creative-tm.everesttech.net/engg?cro=true&auth=9745d24658c9ca5ba47ec85bd74452e4&iid=aThYZgAAASxalwA2&exp=311&aid=461755&crid=25971&def=false&dsp=3&dbid=33686707&dsid=6958819&daid=aThYZgAAASxalwA2&dpid=424555874&dadid=617516314&dcid=238262328&dpp=424555874&uid=aThYZgAAASxamAA2&uidt=EVEREST_COOKIE_ID&ua=Mozilla%2F5.0+%28X11%3B+Ubuntu%3B+Linux+x86_64%3B+rv%3A145.0%29+Gecko%2F20100101+Firefox%2F145.0&tid=874&pc=45223&m=515&c=Cincinnati&reg=OH&cty=US&dppf=t&gpf=t&ppf=f&spf=f&cst=DT_TARGETED&pids=992897&sz=300x600&et=1765300326825";
             }

            var handleStats = function() {
                                    fireBeacon("https://stats-creative-tm.everesttech.net/imp?cro=true&auth=9745d24658c9ca5ba47ec85bd74452e4&iid=aThYZgAAASxalwA2&exp=311&aid=461755&crid=25971&def=false&dsp=3&dbid=33686707&dsid=6958819&daid=aThYZgAAASxalwA2&dpid=424555874&dadid=617516314&dcid=238262328&dpp=424555874&uid=aThYZgAAASxamAA2&uidt=EVEREST_COOKIE_ID&ua=Mozilla%2F5.0+%28X11%3B+Ubuntu%3B+Linux+x86_64%3B+rv%3A145.0%29+Gecko%2F20100101+Firefox%2F145.0&tid=874&pc=45223&m=515&c=Cincinnati&reg=OH&cty=US&dppf=t&gpf=t&ppf=f&spf=f&cst=DT_TARGETED&pids=992897&sz=300x600&et=1765300326825");
                            }

            var notifyClick = function() {}
            

    var createDiv = function (id, styleString, parentDiv) {
        var newDiv = document.createElement("div");
        newDiv.setAttribute("id", id);
        if (styleString && styleString != "") {
            newDiv.setAttribute("style", styleString);
        }
        if (parentDiv) {
            parentDiv.appendChild(newDiv);
        }
        return newDiv;
    }

    var createIFrame = function(div, frmId, width, height, frmSrc, frmContent, callBackFn) {
         if(callBackFn && callBackFn != "") {
            window.addEventListener("message",callBackFn, false);
         }
         var frm = document.getElementById(frmId);
         if (!frm) {
             frm = document.createElement("IFRAME");
             frm.setAttribute("id",frmId);
             frm.style.border= "0";
             frm.style.postion="relative";
             frm.style.top="0px";
             frm.style.left="0px";
             frm.style.width= width + "px";
             frm.style.height= height + "px";
             frm.style.margin="0px";
             frm.setAttribute("frameborder","0");
             frm.setAttribute("scrolling","no");
             if ('allowTransparency' in frm) {
                frm.allowTransparency = true;
             }
             div.appendChild(frm);
             if(frmSrc && frmSrc != "") {
                 frm.src=frmSrc;
             } else if(frmContent && frmContent != "") {
                 try {
                    frm.contentWindow.document.write("<html><head/><body style=\"margin:0px;background-color:transparent;\">" + frmContent + "</body></html>");
                    frm.contentWindow.document.close();
                 } catch(e) {}

             }
         }
         return frm;
    }

    var insertDivs = function () {
        var parent = createDiv("x2_aThYZgAAASxalwA2", "height:600px;width:300px;margin:0 auto;");
        if (document.currentScript) {
            var pn = document.currentScript.parentNode;
            var sbn = document.currentScript.nextSibling;
            if (sbn) {
                pn.insertBefore(parent, sbn);
            } else {
                pn.appendChild(parent);
            }
        } else {
            document.body.appendChild(parent);
        }
    }

    var loadAdDiv = function () {
        if (document.readyState === "complete") {
            insertDivs();
        } else {
            try {
                document.write('<div id="x2_aThYZgAAASxalwA2" style="height:600px;width:300px;margin:0 auto;"></div>');
                document.close();
            } catch(e) {}
        }
    }
        var amo_aThYZgAAASxalwA2 = new Object(); //Creating the master object.
        amo_aThYZgAAASxalwA2.ad = [{gid:"992897",catalog:"MSFT_Azure_US_General_TPV4_Static_Feed_FY26Q2.xlsx",id:"992897",category_id:"0",display_category_name:"",price:"0.00",discount_price:"0.00",brand:"",merchant_id:"391",merchantlogo:"",ship_promo:"",provider:"168868",name:"424555874|EN-US",description:"",rank:"0.0",thumbnailraw:"|001|001|thumbnails/168868/current/dc55f3a2397d52a82cfc59e4dce8aa91.png",product_url:"https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account/search?OCID=AID${TC_1}_OLA_${TC_2}_${TC_3}_${TC_4}",picture_url:"|001|001|rescaled_images/168868/current/dc55f3a2397d52a82cfc59e4dce8aa91.png",image_width:"001",image_height:"001",cpc:"0.0",c_code:"",discount_price_currency:"",blackwhiteliststatus:"0",offer_type:"PRODUCT",cpo:"0.0",baseproductnumber:"992897",country:"US",state:"",city:"",zip:"",dmacode:"",areacode:"",advertiser_category_id:"1965",display_advertiser_category_name:"",ad_size:"300x600",age:"",gender:"",hhi:"",ms:"",segment_id:"",passthroughfield1:"Build on a<br>trusted platform",passthroughfield2:"Get started with a $200 Azure credit.",passthroughfield3:"Sign up",passthroughfield4:"TPV4",passthroughfield5:"NA",text_6:"",text_7:"",text_8:"",text_9:"",profile_filter_5:"",product_sku:"424555874",category:"TPV4Static_Value_304",datapass_filter_4:"",datapass_filter_5:"",image_url:"|001|001|rescaled_images/168868/current/dc55f3a2397d52a82cfc59e4dce8aa91.png",image_url1:"|000|000|source_images/168868/current/1a7566f8b44aa5fd0cdf5b811da7cf11.png",image_url2:"",image_url3:"",image_url4:"",image_url5:"",image_url6:"",image_url7:"",image_url8:"",image_url9:"",image_url10:"",language:"",product_name:"424555874|EN-US",additional_price_1:"0.00",additional_price_2:"0.00",additional_price_3:"0.00",creative_attribute1:"Free Account",creative_attribute2:"Male_Female_Lifestyle_A",creative_attribute3:"Build on a trusted platform",creative_attribute4:"Get started with a $200 Azure credit.",creative_attribute5:"Sign up",creative_attribute_6:"",creative_attribute_7:"",creative_attribute_8:"",creative_attribute_9:"",creative_attribute_10:"",text_1:"",text_2:"",text_3:"",text_4:"",text_5:"",text_10:"",text_11:"",text_12:"",text_13:"",text_14:"",text_15:"",is_default:"F",ut1:"",ut2:"",ut3:"",ut4:"",ut5:""}];
        amo_aThYZgAAASxalwA2.camAttribs={"clickURL":"!{product_url}","layout":"!{passthroughfield4}","ctaText":"!{passthroughfield3}","impressionTracker":"https://analyticspixel.microsoft.com/aid/imp?dcoimpid=(t_td_isn)&$(t_qp_TC_5)","subheadlineText":"!{passthroughfield2}","backgroundImage":"!{image_url1}","headlineText":"!{passthroughfield1}"};
        amo_aThYZgAAASxalwA2.contentBase = "https://creative-assets.everesttech.net/feed/public/";
        amo_aThYZgAAASxalwA2.clickTags = {};
        amo_aThYZgAAASxalwA2.bannerAdHtmlText = '<a target="_blank" href="https://stats-creative-tm.everesttech.net/c?cro=true&auth=9745d24658c9ca5ba47ec85bd74452e4&iid=aThYZgAAASxalwA2&exp=311&aid=461755&crid=25971&def=false&dsp=3&dbid=33686707&dsid=6958819&daid=aThYZgAAASxalwA2&dpid=424555874&dadid=617516314&dcid=238262328&dpp=424555874&uid=aThYZgAAASxamAA2&uidt=EVEREST_COOKIE_ID&ua=Mozilla%2F5.0+%28X11%3B+Ubuntu%3B+Linux+x86_64%3B+rv%3A145.0%29+Gecko%2F20100101+Firefox%2F145.0&tid=874&pc=45223&m=515&c=Cincinnati&reg=OH&cty=US&dppf=t&gpf=t&ppf=f&spf=f&cst=DT_TARGETED&pids=992897&sz=300x600&et=1765300326825&redir=https://azure.microsoft.com/en-us/?v=18.20"><img id="bannerImg" border="0" src="https://creative-assets.everesttech.net/creative/static/assets/461755/0/c899ce6644e58d915a66bb7703ade246/Default_Generic_300x600.png"></img></a>';
        amo_aThYZgAAASxalwA2.clickBeaconArr = [];
        amo_aThYZgAAASxalwA2.efId = "";
        amo_aThYZgAAASxalwA2.skWcid = "";
        amo_aThYZgAAASxalwA2.atsParams = {"x2_tracking_code_1":"cmmy83sj0r2","x2_tracking_code_2":"33686707","x2_tracking_code_3":"424555874","x2_tracking_code_4":"238262328","x2_tracking_code_5":"dcmadvertiserid|8391437$dcmcampaignid|33686707$dcmadid|617516314$dcmrenderingid|237815967$dcmsiteid|6958819$dcmplacementid|424555874$customer|Microsoft$dv360auctionid|ct=US"};
        amo_aThYZgAAASxalwA2.iid = "aThYZgAAASxalwA2";
        amo_aThYZgAAASxalwA2.isn = "aThYZgAAASxalwA2";
        amo_aThYZgAAASxalwA2.isPreview = "false";


        function fireImpBeacon(p_url, paramsObject){
                            	try{
                            		if(p_url && p_url != "null" && p_url != "undefined"){
                            			var timeStamp = new Date().getTime() + "";
                            			var clickTime = paramsObject ? paramsObject.ClickTime: 0;
                            			var beacon = p_url.replace("[timestamp]", timeStamp);
                                        beacon = beacon.replace("^(SEC)", clickTime/1000);
                            			var bImage = new Image();
            							bImage.src = beacon;
            						}
            					}catch(e){

            					}
                            };

        var impBeacons = [];
        for (var i = 0; i < impBeacons.length; i++) {
          fireImpBeacon(impBeacons[i],null);
        }

    function adLoader_aThYZgAAASxalwA2() {};

    var adLoader = function(isn,adwidth,adheight,url,cdnHTML5Url,iid) {

    	var _isn = "";
    	var _adwidth = 0;
    	var _adheight = 0;
    	var _url = "";
    	var _cdnHtml5Url="";
    	var _iid = "";

    	var adLoader = function() {
    		_isn = isn;
    		_adwidth = adwidth;
    		_adheight = adheight;
    		_url=url;
    		_cdnHtml5Url=cdnHTML5Url;
    		_iid = iid;
    	}();

    	var receiveMessage = function(event) {
                if (event.data == 'aThYZgAAASxalwA2') {
                    var iFrm = window.document.getElementById("x2_ad_x2_" + isn);
                    var amoObj = {};
                    amoObj["data"] = window['amo_aThYZgAAASxalwA2']
                    amoObj["mainHtmlFile"] = url;
                    amoObj["isn"] = "aThYZgAAASxalwA2";
                    amoObj["iid"] = "aThYZgAAASxalwA2";
                    iFrm.contentWindow.postMessage(amoObj,"*");
                }
        }

    	var createCDNIFrame = function() {
                var frm = document.getElementById("x2_ad_x2_" + _isn);
                if (!frm) {
                    frm = document.createElement("IFRAME");
                    frm.setAttribute("id","x2_ad_x2_" + _isn);
                    frm.style="border:0;"
                    frm.style.postion="relative";
                    frm.style.top="0px";
                    frm.style.left="0px";
                    frm.style.width= _adwidth + "px";
                    frm.style.height= _adheight + "px";
                    frm.style.margin="0px";
                    frm.setAttribute("scrolling","no");
                    frm.setAttribute("frameborder","0");
                    frm.style.margin = "0";
                    var div=document.getElementById("x2_" + _isn);
                    div.appendChild(frm);
                    frm.src=_cdnHtml5Url + "?data=" + encodeURIComponent(_isn);
                }
                return frm;
            }

    	this.loadAd = function() {
    	  var clickUrl = getClickUrl("${lp_url}");
        amo_aThYZgAAASxalwA2.clickUrl = clickUrl;
        var engUrl = getEngagementUrl();
        amo_aThYZgAAASxalwA2.engUrl = engUrl;

     		window.addEventListener("message", receiveMessage, false);
    		createCDNIFrame();
    	}
    };

    var createiFrame_aThYZgAAASxalwA2 = function(id, styleString, parentDiv)
    {
        var newEle= document.createElement("iFrame");
        newEle.setAttribute("id",id);
        if(styleString && styleString != "" )
        {
            newEle.setAttribute("style", styleString);
        }
        if (parentDiv) {
            parentDiv.appendChild(newEle);
        }
        return newEle;
    }

    var createDiv_aThYZgAAASxalwA2 = function(id, styleString, parentDiv)
    {
        var newDiv= document.createElement("div");
        newDiv.setAttribute("id",id);
        if(styleString && styleString != "" )
        {
            newDiv.setAttribute("style", styleString);
        }
        if (parentDiv) {
            parentDiv.appendChild(newDiv);
        }
        return newDiv;
    };

    var insertDivs_aThYZgAAASxalwA2  = function()
    {
        var parent= createDiv_aThYZgAAASxalwA2("x2_aThYZgAAASxalwA2", "height:600px;width:300px;margin:0 auto;");
        if (document.currentScript) {
            var pn = document.currentScript.parentNode;
            var sbn = document.currentScript.nextSibling;
            if (sbn) {
                pn.insertBefore(parent,sbn);
            } else {
                pn.appendChild(parent);
            }
        } else {
            document.body.appendChild(parent);
        }
        createDiv_aThYZgAAASxalwA2("bannerHtml_aThYZgAAASxalwA2", "margin:0 auto;" , parent);
                var loggingDiv = createDiv_aThYZgAAASxalwA2("amo_aThYZgAAASxalwA2","" ,parent);
        createiFrame_aThYZgAAASxalwA2("clickFrame_aThYZgAAASxalwA2","position: absolute; visibility: hidden; top: 0px; left: 0px; width: 1px; height: 1px;", loggingDiv);
        createiFrame_aThYZgAAASxalwA2("interactionFrame_aThYZgAAASxalwA2","position: absolute; visibility: hidden; top: 0px; left: 0px; width: 1px; height: 1px;", loggingDiv);
    };

    if(document.readyState === "complete")
    {
    	insertDivs_aThYZgAAASxalwA2();
    } else {
      document.write('<div id="x2_aThYZgAAASxalwA2" style="height:600px;width:300px;margin:0 auto;"><div id="bannerHtml_aThYZgAAASxalwA2" style="margin:0 auto;"></div><div id="amo_aThYZgAAASxalwA2"><iframe id="clickFrame_aThYZgAAASxalwA2" style="position: absolute; visibility: hidden; top: 0px; left: 0px; width: 1px; height: 1px;"></iframe></div></div>');
    }

    try {
        var adLoader_inst_aThYZgAAASxalwA2 = new adLoader_aThYZgAAASxalwA2();
        handleStats();
        (new adLoader(
            		"aThYZgAAASxalwA2","300","600",
            		"https://creative-assets.everesttech.net/creative/static/assets/461755/0/d1b9d6786348b447b87e8f1a2e4a2fca/300x600.html",
            		"https://creative-assets.everesttech.net/creative/scripts/html5-dynamic_v1.html","aThYZgAAASxalwA2")
            		).loadAd();
    } catch(e) {
        console.log(e.message);
    }

