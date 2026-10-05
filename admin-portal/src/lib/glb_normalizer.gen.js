// ⚠️ GENERATED FILE — do not edit, and do not hand-fix.
//
// The reference shoe-model normalizer (`lib/utils/glb_normalizer.dart`),
// compiled from `tool/shoe_model_normalizer_web.dart` by:
//
//   node tool/build_shoe_model_normalizer_web.mjs
//
// It is the same `normalizeShoeModel` the CLI runs, not a port of it: the
// eleven-check contract has exactly two implementations (the Dart reference
// and the TypeScript mirror in `validate-shoe-model`, parity-checked over 22
// fixtures) and the portal adds no third. See the Dart entry point for why.
//
// The stamp below is verified by `modelCompress.contract.test.js`, which
// fails with the rebuild command if the Dart has moved on without this file.
//
// dart-source-sha256: 42e1504af534c9a97e07dd4aed4614d953e33416a21481f12c3ff518abafaeaa
// dart-sdk: 3.12.2
(function dartProgram(){function copyProperties(a,b){var t=Object.keys(a)
for(var s=0;s<t.length;s++){var r=t[s]
b[r]=a[r]}}function mixinPropertiesHard(a,b){var t=Object.keys(a)
for(var s=0;s<t.length;s++){var r=t[s]
if(!b.hasOwnProperty(r)){b[r]=a[r]}}}function mixinPropertiesEasy(a,b){Object.assign(b,a)}var z=function(){var t=function(){}
t.prototype={p:{}}
var s=new t()
if(!(Object.getPrototypeOf(s)&&Object.getPrototypeOf(s).p===t.prototype.p))return false
try{if(typeof navigator!="undefined"&&typeof navigator.userAgent=="string"&&navigator.userAgent.indexOf("Chrome/")>=0)return true
if(typeof version=="function"&&version.length==0){var r=version()
if(/^\d+\.\d+\.\d+\.\d+$/.test(r))return true}}catch(q){}return false}()
function inherit(a,b){a.prototype.constructor=a
a.prototype["$i"+a.name]=a
if(b!=null){if(z){Object.setPrototypeOf(a.prototype,b.prototype)
return}var t=Object.create(b.prototype)
copyProperties(a.prototype,t)
a.prototype=t}}function inheritMany(a,b){for(var t=0;t<b.length;t++){inherit(b[t],a)}}function mixinEasy(a,b){mixinPropertiesEasy(b.prototype,a.prototype)
a.prototype.constructor=a}function mixinHard(a,b){mixinPropertiesHard(b.prototype,a.prototype)
a.prototype.constructor=a}function lazy(a,b,c,d){var t=a
a[b]=t
a[c]=function(){if(a[b]===t){a[b]=d()}a[c]=function(){return this[b]}
return a[b]}}function lazyFinal(a,b,c,d){var t=a
a[b]=t
a[c]=function(){if(a[b]===t){var s=d()
if(a[b]!==t){A.qn(b)}a[b]=s}var r=a[b]
a[c]=function(){return r}
return r}}function makeConstList(a,b){if(b!=null)A.j(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var t=0;t<a.length;++t){convertToFastObject(a[t])}}var y=0
function instanceTearOffGetter(a,b){var t=null
return a?function(c){if(t===null)t=A.kz(b)
return new t(c,this)}:function(){if(t===null)t=A.kz(b)
return new t(this,null)}}function staticTearOffGetter(a){var t=null
return function(){if(t===null)t=A.kz(a).prototype
return t}}var x=0
function tearOffParameters(a,b,c,d,e,f,g,h,i,j){if(typeof h=="number"){h+=x}return{co:a,iS:b,iI:c,rC:d,dV:e,cs:f,fs:g,fT:h,aI:i||0,nDA:j}}function installStaticTearOff(a,b,c,d,e,f,g,h){var t=tearOffParameters(a,true,false,c,d,e,f,g,h,false)
var s=staticTearOffGetter(t)
a[b]=s}function installInstanceTearOff(a,b,c,d,e,f,g,h,i,j){c=!!c
var t=tearOffParameters(a,false,c,d,e,f,g,h,i,!!j)
var s=instanceTearOffGetter(c,t)
a[b]=s}function setOrUpdateInterceptorsByTag(a){var t=v.interceptorsByTag
if(!t){v.interceptorsByTag=a
return}copyProperties(a,t)}function setOrUpdateLeafTags(a){var t=v.leafTags
if(!t){v.leafTags=a
return}copyProperties(a,t)}function updateTypes(a){var t=v.types
var s=t.length
t.push.apply(t,a)
return s}function updateHolder(a,b){copyProperties(b,a)
return a}var hunkHelpers=function(){var t=function(a,b,c,d,e){return function(f,g,h,i){return installInstanceTearOff(f,g,a,b,c,d,[h],i,e,false)}},s=function(a,b,c,d){return function(e,f,g,h){return installStaticTearOff(e,f,a,b,c,[g],h,d)}}
return{inherit:inherit,inheritMany:inheritMany,mixin:mixinEasy,mixinHard:mixinHard,installStaticTearOff:installStaticTearOff,installInstanceTearOff:installInstanceTearOff,_instance_0u:t(0,0,null,["$0"],0),_instance_1u:t(0,1,null,["$1"],0),_instance_2u:t(0,2,null,["$2"],0),_instance_0i:t(1,0,null,["$0"],0),_instance_1i:t(1,1,null,["$1"],0),_instance_2i:t(1,2,null,["$2"],0),_static_0:s(0,null,["$0"],0),_static_1:s(1,null,["$1"],0),_static_2:s(2,null,["$2"],0),makeConstList:makeConstList,lazy:lazy,lazyFinal:lazyFinal,updateHolder:updateHolder,convertToFastObject:convertToFastObject,updateTypes:updateTypes,setOrUpdateInterceptorsByTag:setOrUpdateInterceptorsByTag,setOrUpdateLeafTags:setOrUpdateLeafTags}}()
function initializeDeferredHunk(a){x=v.types.length
a(hunkHelpers,v,w,$)}var J={
kD(a,b,c,d){return{i:a,p:b,e:c,x:d}},
jA(a){var t,s,r,q,p,o=a[v.dispatchPropertyName]
if(o==null)if($.kB==null){A.q9()
o=a[v.dispatchPropertyName]}if(o!=null){t=o.p
if(!1===t)return o.i
if(!0===t)return a
s=Object.getPrototypeOf(a)
if(t===s)return o.i
if(o.e===s)throw A.f(A.lJ("Return interceptor for "+A.z(t(a,o))))}r=a.constructor
if(r==null)q=null
else{p=$.iN
if(p==null)p=$.iN=v.getIsolateTag("_$dart_js")
q=r[p]}if(q!=null)return q
q=A.qf(a)
if(q!=null)return q
if(typeof a=="function")return B.d8
t=Object.getPrototypeOf(a)
if(t==null)return B.bU
if(t===Object.prototype)return B.bU
if(typeof r=="function"){p=$.iN
if(p==null)p=$.iN=v.getIsolateTag("_$dart_js")
Object.defineProperty(r,p,{value:B.aJ,enumerable:false,writable:true,configurable:true})
return B.aJ}return B.aJ},
lk(a,b){if(a<0||a>4294967295)throw A.f(A.ak(a,0,4294967295,"length",null))
return J.ll(new Array(a),b)},
ag(a,b){if(a<0||a>4294967295)throw A.f(A.ak(a,0,4294967295,"length",null))
return J.ll(new Array(a),b)},
k_(a,b){if(a<0)throw A.f(A.bQ("Length must be a non-negative integer: "+a))
return A.j(new Array(a),b.v("r<0>"))},
c4(a,b){if(a<0)throw A.f(A.bQ("Length must be a non-negative integer: "+a))
return A.j(new Array(a),b.v("r<0>"))},
ll(a,b){var t=A.j(a,b.v("r<0>"))
t.$flags=1
return t},
lm(a,b){var t=u.W
return J.mO(t.a(a),t.a(b))},
ln(a){if(a<256)switch(a){case 9:case 10:case 11:case 12:case 13:case 32:case 133:case 160:return!0
default:return!1}switch(a){case 5760:case 8192:case 8193:case 8194:case 8195:case 8196:case 8197:case 8198:case 8199:case 8200:case 8201:case 8202:case 8232:case 8233:case 8239:case 8287:case 12288:case 65279:return!0
default:return!1}},
nk(a,b){var t,s
for(t=a.length;b<t;){s=a.charCodeAt(b)
if(s!==32&&s!==13&&!J.ln(s))break;++b}return b},
nl(a,b){var t,s,r
for(t=a.length;b>0;b=s){s=b-1
if(!(s<t))return A.a(a,s)
r=a.charCodeAt(s)
if(r!==32&&r!==13&&!J.ln(r))break}return b},
bt(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.dM.prototype
return J.fx.prototype}if(typeof a=="string")return J.c5.prototype
if(a==null)return J.dN.prototype
if(typeof a=="boolean")return J.fw.prototype
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.bi.prototype
if(typeof a=="symbol")return J.d0.prototype
if(typeof a=="bigint")return J.d_.prototype
return a}if(a instanceof A.H)return a
return J.jA(a)},
S(a){if(typeof a=="string")return J.c5.prototype
if(a==null)return a
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.bi.prototype
if(typeof a=="symbol")return J.d0.prototype
if(typeof a=="bigint")return J.d_.prototype
return a}if(a instanceof A.H)return a
return J.jA(a)},
aI(a){if(a==null)return a
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.bi.prototype
if(typeof a=="symbol")return J.d0.prototype
if(typeof a=="bigint")return J.d_.prototype
return a}if(a instanceof A.H)return a
return J.jA(a)},
q5(a){if(typeof a=="number")return J.cZ.prototype
if(typeof a=="string")return J.c5.prototype
if(a==null)return a
if(!(a instanceof A.H))return J.dc.prototype
return a},
b7(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.bi.prototype
if(typeof a=="symbol")return J.d0.prototype
if(typeof a=="bigint")return J.d_.prototype
return a}if(a instanceof A.H)return a
return J.jA(a)},
bO(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.bt(a).S(a,b)},
c(a,b){if(typeof b==="number")if(Array.isArray(a)||typeof a=="string"||A.qd(a,a[v.dispatchPropertyName]))if(b>>>0===b&&b<a.length)return a[b]
return J.S(a).k(a,b)},
x(a,b,c){return J.aI(a).i(a,b,c)},
mK(a,b,c){return J.b7(a).eO(a,b,c)},
kO(a,b,c){return J.b7(a).eP(a,b,c)},
mL(a,b,c){return J.b7(a).eQ(a,b,c)},
mM(a,b,c){return J.b7(a).eR(a,b,c)},
jL(a,b,c){return J.b7(a).eS(a,b,c)},
mN(a){return J.b7(a).eT(a)},
kP(a,b,c){return J.b7(a).d1(a,b,c)},
aw(a,b,c){return J.b7(a).eU(a,b,c)},
ab(a){return J.b7(a).eV(a)},
V(a,b,c){return J.b7(a).d2(a,b,c)},
mO(a,b){return J.q5(a).cl(a,b)},
kQ(a,b){return J.aI(a).bv(a,b)},
b9(a,b,c,d){return J.aI(a).aB(a,b,c,d)},
bP(a){return J.bt(a).gH(a)},
mP(a){return J.S(a).gaU(a)},
kR(a){return J.S(a).gdK(a)},
bu(a){return J.aI(a).gI(a)},
ao(a){return J.S(a).gt(a)},
mQ(a){return J.bt(a).gaE(a)},
ba(a,b,c){return J.aI(a).f8(a,b,c)},
kS(a,b,c){return J.b7(a).d9(a,b,c)},
jM(a,b){return J.aI(a).da(a,b)},
jN(a,b,c){return J.aI(a).b6(a,b,c)},
mR(a,b){return J.aI(a).fe(a,b)},
ac(a){return J.bt(a).D(a)},
fk:function fk(){},
fw:function fw(){},
dN:function dN(){},
dO:function dO(){},
bB:function bB(){},
fI:function fI(){},
dc:function dc(){},
bi:function bi(){},
d_:function d_(){},
d0:function d0(){},
r:function r(a){this.$ti=a},
fv:function fv(){},
hR:function hR(a){this.$ti=a},
bR:function bR(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
cZ:function cZ(){},
dM:function dM(){},
fx:function fx(){},
c5:function c5(){}},A={k0:function k0(){},
lq(a){return new A.d1("Field '"+a+"' has not been initialized.")},
nm(a){return new A.d1("Field '"+a+"' has already been initialized.")},
bm(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
ig(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
md(a,b,c){return a},
kC(a){var t,s
for(t=$.aH.length,s=0;s<t;++s)if(a===$.aH[s])return!0
return!1},
ep(a,b,c,d){A.d8(b,"start")
if(c!=null){A.d8(c,"end")
if(b>c)A.aA(A.ak(b,0,c,"start",null))}return new A.eo(a,b,c,d.v("eo<0>"))},
jY(){return new A.da("No element")},
lj(){return new A.da("Too few elements")},
iI:function iI(a){this.a=0
this.b=a},
d1:function d1(a){this.a=a},
aJ:function aJ(a){this.a=a},
ie:function ie(){},
dp:function dp(){},
a1:function a1(){},
eo:function eo(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
bk:function bk(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
c6:function c6(a,b,c){this.a=a
this.b=b
this.$ti=c},
bs:function bs(a,b,c){this.a=a
this.b=b
this.$ti=c},
eA:function eA(a,b,c){this.a=a
this.b=b
this.$ti=c},
dq:function dq(a){this.$ti=a},
dr:function dr(a){this.$ti=a},
ax:function ax(){},
bp:function bp(){},
dd:function dd(){},
n0(){throw A.f(A.b5("Cannot modify constant Set"))},
mn(a){var t=v.mangledGlobalNames[a]
if(t!=null)return t
return"minified:"+a},
qd(a,b){var t
if(b!=null){t=b.x
if(t!=null)return t}return u.eA.b(a)},
z(a){var t
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
t=J.ac(a)
return t},
ei(a){var t,s=$.lA
if(s==null)s=$.lA=Symbol("identityHashCode")
t=a[s]
if(t==null){t=Math.random()*0x3fffffff|0
a[s]=t}return t},
nD(a,b){var t,s=/^\s*[+-]?((0x[a-f0-9]+)|(\d+)|([a-z0-9]+))\s*$/i.exec(a)
if(s==null)return null
if(3>=s.length)return A.a(s,3)
t=s[3]
if(t!=null)return parseInt(a,10)
if(s[2]!=null)return parseInt(a,16)
return null},
fL(a){var t,s,r,q
if(a instanceof A.H)return A.aG(A.aR(a),null)
t=J.bt(a)
if(t===B.d6||t===B.d9||u.bI.b(a)){s=B.aN(a)
if(s!=="Object"&&s!=="")return s
r=a.constructor
if(typeof r=="function"){q=r.name
if(typeof q=="string"&&q!=="Object"&&q!=="")return q}}return A.aG(A.aR(a),null)},
nE(a){var t,s,r
if(typeof a=="number"||A.kx(a))return J.ac(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.bv)return a.D(0)
t=$.mI()
for(s=0;s<1;++s){r=t[s].jB(a)
if(r!=null)return r}return"Instance of '"+A.fL(a)+"'"},
lz(a){var t,s,r,q,p=a.length
if(p<=500)return String.fromCharCode.apply(null,a)
for(t="",s=0;s<p;s=r){r=s+500
q=r<p?r:p
t+=String.fromCharCode.apply(null,a.slice(s,q))}return t},
nF(a){var t,s,r,q=A.j([],u.t)
for(t=a.length,s=0;s<a.length;a.length===t||(0,A.a_)(a),++s){r=a[s]
if(!A.j3(r))throw A.f(A.bM(r))
if(r<=65535)B.c.A(q,r)
else if(r<=1114111){B.c.A(q,55296+(B.a.j(r-65536,10)&1023))
B.c.A(q,56320+(r&1023))}else throw A.f(A.bM(r))}return A.lz(q)},
lB(a){var t,s,r
for(t=a.length,s=0;s<t;++s){r=a[s]
if(!A.j3(r))throw A.f(A.bM(r))
if(r<0)throw A.f(A.bM(r))
if(r>65535)return A.nF(a)}return A.lz(a)},
nG(a,b,c){var t,s,r,q
if(c<=500&&b===0&&c===a.length)return String.fromCharCode.apply(null,a)
for(t=b,s="";t<c;t=r){r=t+500
q=r<c?r:c
s+=String.fromCharCode.apply(null,a.subarray(t,q))}return s},
W(a){var t
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){t=a-65536
return String.fromCharCode((B.a.j(t,10)|55296)>>>0,t&1023|56320)}throw A.f(A.ak(a,0,1114111,null,null))},
hn(a){throw A.f(A.bM(a))},
a(a,b){if(a==null)J.ao(a)
throw A.f(A.jr(a,b))},
jr(a,b){var t,s="index"
if(!A.j3(b))return new A.bb(!0,b,s,null)
t=J.ao(a)
if(b<0||b>=t)return A.jV(b,t,a,s)
return A.lE(b,s)},
pZ(a,b,c){if(a<0||a>c)return A.ak(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.ak(b,a,c,"end",null)
return new A.bb(!0,b,"end",null)},
bM(a){return new A.bb(!0,a,null,null)},
f(a){return A.a9(a,new Error())},
a9(a,b){var t
if(a==null)a=new A.er()
b.dartException=a
t=A.qo
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:t})
b.name=""}else b.toString=t
return b},
qo(){return J.ac(this.dartException)},
aA(a,b){throw A.a9(a,b==null?new Error():b)},
b(a,b,c){var t
if(b==null)b=0
if(c==null)c=0
t=Error()
A.aA(A.p7(a,b,c),t)},
p7(a,b,c){var t,s,r,q,p,o,n,m,l
if(typeof b=="string")t=b
else{s="[]=;add;removeWhere;retainWhere;removeRange;setRange;setInt8;setInt16;setInt32;setUint8;setUint16;setUint32;setFloat32;setFloat64".split(";")
r=s.length
q=b
if(q>r){c=q/r|0
q%=r}t=s[q]}p=typeof c=="string"?c:"modify;remove from;add to".split(";")[c]
o=u.j.b(a)?"list":"ByteData"
n=a.$flags|0
m="a "
if((n&4)!==0)l="constant "
else if((n&2)!==0){l="unmodifiable "
m="an "}else l=(n&1)!==0?"fixed-length ":""
return new A.es("'"+t+"': Cannot "+p+" "+m+l+o)},
a_(a){throw A.f(A.b2(a))},
bn(a){var t,s,r,q,p,o
a=A.qj(a.replace(String({}),"$receiver$"))
t=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(t==null)t=A.j([],u.s)
s=t.indexOf("\\$arguments\\$")
r=t.indexOf("\\$argumentsExpr\\$")
q=t.indexOf("\\$expr\\$")
p=t.indexOf("\\$method\\$")
o=t.indexOf("\\$receiver\\$")
return new A.il(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),s,r,q,p,o)},
im(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(t){return t.message}}(a)},
lH(a){return function($expr$){try{$expr$.$method$}catch(t){return t.message}}(a)},
k1(a,b){var t=b==null,s=t?null:b.method
return new A.fB(a,s,t?null:b.receiver)},
kH(a){if(a==null)return new A.i3(a)
if(typeof a!=="object")return a
if("dartException" in a)return A.cx(a,a.dartException)
return A.pQ(a)},
cx(a,b){if(u.bU.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
pQ(a){var t,s,r,q,p,o,n,m,l,k,j,i,h
if(!("message" in a))return a
t=a.message
if("number" in a&&typeof a.number=="number"){s=a.number
r=s&65535
if((B.a.j(s,16)&8191)===10)switch(r){case 438:return A.cx(a,A.k1(A.z(t)+" (Error "+r+")",null))
case 445:case 5007:A.z(t)
return A.cx(a,new A.e2())}}if(a instanceof TypeError){q=$.ms()
p=$.mt()
o=$.mu()
n=$.mv()
m=$.my()
l=$.mz()
k=$.mx()
$.mw()
j=$.mB()
i=$.mA()
h=q.bx(t)
if(h!=null)return A.cx(a,A.k1(A.b0(t),h))
else{h=p.bx(t)
if(h!=null){h.method="call"
return A.cx(a,A.k1(A.b0(t),h))}else if(o.bx(t)!=null||n.bx(t)!=null||m.bx(t)!=null||l.bx(t)!=null||k.bx(t)!=null||n.bx(t)!=null||j.bx(t)!=null||i.bx(t)!=null){A.b0(t)
return A.cx(a,new A.e2())}}return A.cx(a,new A.h4(typeof t=="string"?t:""))}if(a instanceof RangeError){if(typeof t=="string"&&t.indexOf("call stack")!==-1)return new A.em()
t=function(b){try{return String(b)}catch(g){}return null}(a)
return A.cx(a,new A.bb(!1,null,null,typeof t=="string"?t.replace(/^RangeError:\s*/,""):t))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof t=="string"&&t==="too much recursion")return new A.em()
return a},
kE(a){if(a==null)return J.bP(a)
if(typeof a=="object")return A.ei(a)
return J.bP(a)},
pT(a){if(typeof a=="number")return B.b.gH(a)
if(a instanceof A.hh)return A.ei(a)
return A.kE(a)},
mg(a,b){var t,s,r,q=a.length
for(t=0;t<q;t=r){s=t+1
r=s+1
b.i(0,a[t],a[s])}return b},
ph(a,b,c,d,e,f){u.Z.a(a)
switch(A.u(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.f(new A.iK("Unsupported number of arguments for wrapped closure"))},
pU(a,b){var t=a.$identity
if(!!t)return t
t=A.pV(a,b)
a.$identity=t
return t},
pV(a,b){var t
switch(b){case 0:t=a.$0
break
case 1:t=a.$1
break
case 2:t=a.$2
break
case 3:t=a.$3
break
case 4:t=a.$4
break
default:t=null}if(t!=null)return t.bind(a)
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.ph)},
n_(a1){var t,s,r,q,p,o,n,m,l,k,j=a1.co,i=a1.iS,h=a1.iI,g=a1.nDA,f=a1.aI,e=a1.fs,d=a1.cs,c=e[0],b=d[0],a=j[c],a0=a1.fT
a0.toString
t=i?Object.create(new A.fY().constructor.prototype):Object.create(new A.cy(null,null).constructor.prototype)
t.$initialize=t.constructor
s=i?function static_tear_off(){this.$initialize()}:function tear_off(a2,a3){this.$initialize(a2,a3)}
t.constructor=s
s.prototype=t
t.$_name=c
t.$_target=a
r=!i
if(r)q=A.kZ(c,a,h,g)
else{t.$static_name=c
q=a}t.$S=A.mW(a0,i,h)
t[b]=q
for(p=q,o=1;o<e.length;++o){n=e[o]
if(typeof n=="string"){m=j[n]
l=n
n=m}else l=""
k=d[o]
if(k!=null){if(r)n=A.kZ(l,n,h,g)
t[k]=n}if(o===f)p=n}t.$C=p
t.$R=a1.rC
t.$D=a1.dV
return s},
mW(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.f("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.mT)}throw A.f("Error in functionType of tearoff")},
mX(a,b,c,d){var t=A.kY
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,t)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,t)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,t)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,t)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,t)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,t)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,t)}},
kZ(a,b,c,d){if(c)return A.mZ(a,b,d)
return A.mX(b.length,d,a,b)},
mY(a,b,c,d){var t=A.kY,s=A.mU
switch(b?-1:a){case 0:throw A.f(new A.fX("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,s,t)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,s,t)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,s,t)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,s,t)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,s,t)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,s,t)
default:return function(e,f,g){return function(){var r=[g(this)]
Array.prototype.push.apply(r,arguments)
return e.apply(f(this),r)}}(d,s,t)}},
mZ(a,b,c){var t,s
if($.kW==null)$.kW=A.kV("interceptor")
if($.kX==null)$.kX=A.kV("receiver")
t=b.length
s=A.mY(t,c,a,b)
return s},
kz(a){return A.n_(a)},
mT(a,b){return A.iU(v.typeUniverse,A.aR(a.a),b)},
kY(a){return a.a},
mU(a){return a.b},
kV(a){var t,s,r,q=new A.cy("receiver","interceptor"),p=Object.getOwnPropertyNames(q)
p.$flags=1
t=p
for(p=t.length,s=0;s<p;++s){r=t[s]
if(q[r]===a)return r}throw A.f(A.bQ("Field name "+a+" not found."))},
mi(a){return v.getIsolateTag(a)},
rL(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
qf(a){var t,s,r,q,p,o=A.b0($.mj.$1(a)),n=$.js[o]
if(n!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:n,enumerable:false,writable:true,configurable:true})
return n.i}t=$.jE[o]
if(t!=null)return t
s=v.interceptorsByTag[o]
if(s==null){r=A.ku($.mc.$2(a,o))
if(r!=null){n=$.js[r]
if(n!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:n,enumerable:false,writable:true,configurable:true})
return n.i}t=$.jE[r]
if(t!=null)return t
s=v.interceptorsByTag[r]
o=r}}if(s==null)return null
t=s.prototype
q=o[0]
if(q==="!"){n=A.jF(t)
$.js[o]=n
Object.defineProperty(a,v.dispatchPropertyName,{value:n,enumerable:false,writable:true,configurable:true})
return n.i}if(q==="~"){$.jE[o]=t
return t}if(q==="-"){p=A.jF(t)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:p,enumerable:false,writable:true,configurable:true})
return p.i}if(q==="+")return A.mk(a,t)
if(q==="*")throw A.f(A.lJ(o))
if(v.leafTags[o]===true){p=A.jF(t)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:p,enumerable:false,writable:true,configurable:true})
return p.i}else return A.mk(a,t)},
mk(a,b){var t=Object.getPrototypeOf(a)
Object.defineProperty(t,v.dispatchPropertyName,{value:J.kD(b,t,null,null),enumerable:false,writable:true,configurable:true})
return b},
jF(a){return J.kD(a,!1,null,!!a.$iaL)},
qh(a,b,c){var t=b.prototype
if(v.leafTags[a]===true)return A.jF(t)
else return J.kD(t,c,null,null)},
q9(){if(!0===$.kB)return
$.kB=!0
A.qa()},
qa(){var t,s,r,q,p,o,n,m
$.js=Object.create(null)
$.jE=Object.create(null)
A.q8()
t=v.interceptorsByTag
s=Object.getOwnPropertyNames(t)
if(typeof window!="undefined"){window
r=function(){}
for(q=0;q<s.length;++q){p=s[q]
o=$.ml.$1(p)
if(o!=null){n=A.qh(p,t[p],o)
if(n!=null){Object.defineProperty(o,v.dispatchPropertyName,{value:n,enumerable:false,writable:true,configurable:true})
r.prototype=o}}}}for(q=0;q<s.length;++q){p=s[q]
if(/^[A-Za-z_]/.test(p)){m=t[p]
t["!"+p]=m
t["~"+p]=m
t["-"+p]=m
t["+"+p]=m
t["*"+p]=m}}},
q8(){var t,s,r,q,p,o,n=B.ct()
n=A.dj(B.cu,A.dj(B.cv,A.dj(B.aO,A.dj(B.aO,A.dj(B.cw,A.dj(B.cx,A.dj(B.cy(B.aN),n)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){t=dartNativeDispatchHooksTransformer
if(typeof t=="function")t=[t]
if(Array.isArray(t))for(s=0;s<t.length;++s){r=t[s]
if(typeof r=="function")n=r(n)||n}}q=n.getTag
p=n.getUnknownTag
o=n.prototypeForTag
$.mj=new A.jB(q)
$.mc=new A.jC(p)
$.ml=new A.jD(o)},
dj(a,b){return a(b)||b},
pY(a,b){var t=b.length,s=v.rttc[""+t+";"+a]
if(s==null)return null
if(t===0)return s
if(t===s.length)return s.apply(null,b)
return s(b)},
qk(a,b,c){var t=a.indexOf(b,c)
return t>=0},
qj(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
ql(a,b,c,d){var t=a.indexOf(b,d)
if(t<0)return a
return A.qm(a,t,t+b.length,c)},
qm(a,b,c,d){return a.substring(0,b)+d+a.substring(c)},
cK:function cK(){},
dn:function dn(a,b,c){this.a=a
this.b=b
this.$ti=c},
eB:function eB(a,b){this.a=a
this.$ti=b},
cq:function cq(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bX:function bX(a,b){this.a=a
this.$ti=b},
dm:function dm(){},
bU:function bU(a,b,c){this.a=a
this.b=b
this.$ti=c},
el:function el(){},
il:function il(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
e2:function e2(){},
fB:function fB(a,b,c){this.a=a
this.b=b
this.c=c},
h4:function h4(a){this.a=a},
i3:function i3(a){this.a=a},
bv:function bv(){},
eT:function eT(){},
eU:function eU(){},
h_:function h_(){},
fY:function fY(){},
cy:function cy(a,b){this.a=a
this.b=b},
fX:function fX(a){this.a=a},
aV:function aV(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
i_:function i_(a,b){var _=this
_.a=a
_.b=b
_.d=_.c=null},
bj:function bj(a,b){this.a=a
this.$ti=b},
O:function O(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
dR:function dR(a,b){this.a=a
this.$ti=b},
aq:function aq(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
dP:function dP(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
jB:function jB(a){this.a=a},
jC:function jC(a){this.a=a},
jD:function jD(a){this.a=a},
fZ:function fZ(a,b){this.a=a
this.c=b},
iR:function iR(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=null},
qn(a){throw A.a9(new A.d1("Field '"+a+"' has been assigned during initialization."),new Error())},
d(){throw A.a9(A.lq(""),new Error())},
kG(){throw A.a9(A.nm(""),new Error())},
oz(){var t=new A.iH()
return t.b=t},
iH:function iH(){this.b=null},
at(a,b,c){},
w(a){var t,s,r
if(u.aP.b(a))return a
t=J.S(a)
s=A.P(t.gt(a),null,!1,u.z)
for(r=0;r<t.gt(a);++r)B.c.i(s,r,t.k(a,r))
return s},
np(a,b,c){var t
A.at(a,b,c)
t=new DataView(a,b,c)
return t},
nq(a){return new Float32Array(a)},
nr(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Float32Array(a,b,c)},
ns(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,2)
return new Int16Array(a,b,c)},
nt(a){return new Int32Array(a)},
nu(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Int32Array(a,b,c)},
lw(a){return new Int8Array(a)},
nv(a,b,c){A.at(a,b,c)
return c==null?new Int8Array(a,b):new Int8Array(a,b,c)},
nw(a){return new Uint16Array(a)},
nx(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,2)
return new Uint16Array(a,b,c)},
ny(a){return new Uint32Array(a)},
nz(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Uint32Array(a,b,c)},
e0(a){return new Uint8Array(a)},
k4(a){return new Uint8Array(A.w(a))},
nA(a,b,c){A.at(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
bL(a,b,c){if(a>>>0!==a||a>=c)throw A.f(A.jr(b,a))},
b6(a,b,c){var t
if(!(a>>>0!==a))if(b==null)t=a>c
else t=b>>>0!==b||a>b||b>c
else t=!0
if(t)throw A.f(A.pZ(a,b,c))
if(b==null)return c
return b},
c7:function c7(){},
dY:function dY(){},
iV:function iV(a){this.a=a},
dS:function dS(){},
aj:function aj(){},
bC:function bC(){},
aM:function aM(){},
dT:function dT(){},
dU:function dU(){},
dV:function dV(){},
dW:function dW(){},
dX:function dX(){},
dZ:function dZ(){},
e_:function e_(){},
c8:function c8(){},
eD:function eD(){},
eE:function eE(){},
eF:function eF(){},
eG:function eG(){},
kl(a,b){var t=b.c
return t==null?b.c=A.eL(a,"l3",[b.x]):t},
lF(a){var t=a.w
if(t===6||t===7)return A.lF(a.x)
return t===11||t===12},
nJ(a){return a.as},
Z(a){return A.iT(v.typeUniverse,a,!1)},
ct(a0,a1,a2,a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a=a1.w
switch(a){case 5:case 1:case 2:case 3:case 4:return a1
case 6:t=a1.x
s=A.ct(a0,t,a2,a3)
if(s===t)return a1
return A.lV(a0,s,!0)
case 7:t=a1.x
s=A.ct(a0,t,a2,a3)
if(s===t)return a1
return A.lU(a0,s,!0)
case 8:r=a1.y
q=A.di(a0,r,a2,a3)
if(q===r)return a1
return A.eL(a0,a1.x,q)
case 9:p=a1.x
o=A.ct(a0,p,a2,a3)
n=a1.y
m=A.di(a0,n,a2,a3)
if(o===p&&m===n)return a1
return A.ks(a0,o,m)
case 10:l=a1.x
k=a1.y
j=A.di(a0,k,a2,a3)
if(j===k)return a1
return A.lW(a0,l,j)
case 11:i=a1.x
h=A.ct(a0,i,a2,a3)
g=a1.y
f=A.pM(a0,g,a2,a3)
if(h===i&&f===g)return a1
return A.lT(a0,h,f)
case 12:e=a1.y
a3+=e.length
d=A.di(a0,e,a2,a3)
p=a1.x
o=A.ct(a0,p,a2,a3)
if(d===e&&o===p)return a1
return A.kt(a0,o,d,!0)
case 13:c=a1.x
if(c<a3)return a1
b=a2[c-a3]
if(b==null)return a1
return b
default:throw A.f(A.eP("Attempted to substitute unexpected RTI kind "+a))}},
di(a,b,c,d){var t,s,r,q,p=b.length,o=A.iZ(p)
for(t=!1,s=0;s<p;++s){r=b[s]
q=A.ct(a,r,c,d)
if(q!==r)t=!0
o[s]=q}return t?o:b},
pN(a,b,c,d){var t,s,r,q,p,o,n=b.length,m=A.iZ(n)
for(t=!1,s=0;s<n;s+=3){r=b[s]
q=b[s+1]
p=b[s+2]
o=A.ct(a,p,c,d)
if(o!==p)t=!0
m.splice(s,3,r,q,o)}return t?m:b},
pM(a,b,c,d){var t,s=b.a,r=A.di(a,s,c,d),q=b.b,p=A.di(a,q,c,d),o=b.c,n=A.pN(a,o,c,d)
if(r===s&&p===q&&n===o)return b
t=new A.hd()
t.a=r
t.b=p
t.c=n
return t},
j(a,b){a[v.arrayRti]=b
return a},
me(a){var t=a.$S
if(t!=null){if(typeof t=="number")return A.q7(t)
return a.$S()}return null},
qb(a,b){var t
if(A.lF(b))if(a instanceof A.bv){t=A.me(a)
if(t!=null)return t}return A.aR(a)},
aR(a){if(a instanceof A.H)return A.l(a)
if(Array.isArray(a))return A.al(a)
return A.kw(J.bt(a))},
al(a){var t=a[v.arrayRti],s=u.b
if(t==null)return s
if(t.constructor!==s.constructor)return s
return t},
l(a){var t=a.$ti
return t!=null?t:A.kw(a)},
kw(a){var t=a.constructor,s=t.$ccache
if(s!=null)return s
return A.pf(a,t)},
pf(a,b){var t=a instanceof A.bv?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,s=A.oQ(v.typeUniverse,t.name)
b.$ccache=s
return s},
q7(a){var t,s=v.types,r=s[a]
if(typeof r=="string"){t=A.iT(v.typeUniverse,r,!1)
s[a]=t
return t}return r},
q6(a){return A.cu(A.l(a))},
pL(a){var t=a instanceof A.bv?A.me(a):null
if(t!=null)return t
if(u.ci.b(a))return J.mQ(a).a
if(Array.isArray(a))return A.al(a)
return A.aR(a)},
cu(a){var t=a.r
return t==null?a.r=new A.hh(a):t},
b8(a){return A.cu(A.iT(v.typeUniverse,a,!1))},
pe(a){var t=this
t.b=A.pK(t)
return t.b(a)},
pK(a){var t,s,r,q,p
if(a===u.K)return A.pn
if(A.cw(a))return A.pr
t=a.w
if(t===6)return A.pc
if(t===1)return A.m6
if(t===7)return A.pi
s=A.pJ(a)
if(s!=null)return s
if(t===8){r=a.x
if(a.y.every(A.cw)){a.f="$i"+r
if(r==="p")return A.pl
if(a===u.m)return A.pk
return A.pq}}else if(t===10){q=A.pY(a.x,a.y)
p=q==null?A.m6:q
return p==null?A.j0(p):p}return A.pa},
pJ(a){if(a.w===8){if(a===u.p)return A.j3
if(a===u.i||a===u.q)return A.pm
if(a===u.N)return A.pp
if(a===u.y)return A.kx}return null},
pd(a){var t=this,s=A.p9
if(A.cw(t))s=A.p0
else if(t===u.K)s=A.j0
else if(A.dk(t)){s=A.pb
if(t===u.I)s=A.oY
else if(t===u.dk)s=A.ku
else if(t===u.fQ)s=A.oW
else if(t===u.cg)s=A.Q
else if(t===u.cD)s=A.oX
else if(t===u.bX)s=A.p_}else if(t===u.p)s=A.u
else if(t===u.N)s=A.b0
else if(t===u.y)s=A.oV
else if(t===u.q)s=A.bK
else if(t===u.i)s=A.m0
else if(t===u.m)s=A.oZ
t.a=s
return t.a(a)},
pa(a){var t=this
if(a==null)return A.dk(t)
return A.qe(v.typeUniverse,A.qb(a,t),t)},
pc(a){if(a==null)return!0
return this.x.b(a)},
pq(a){var t,s=this
if(a==null)return A.dk(s)
t=s.f
if(a instanceof A.H)return!!a[t]
return!!J.bt(a)[t]},
pl(a){var t,s=this
if(a==null)return A.dk(s)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
t=s.f
if(a instanceof A.H)return!!a[t]
return!!J.bt(a)[t]},
pk(a){var t=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.H)return!!a[t.f]
return!0}if(typeof a=="function")return!0
return!1},
m5(a){if(typeof a=="object"){if(a instanceof A.H)return u.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
p9(a){var t=this
if(a==null){if(A.dk(t))return a}else if(t.b(a))return a
throw A.a9(A.m1(a,t),new Error())},
pb(a){var t=this
if(a==null||t.b(a))return a
throw A.a9(A.m1(a,t),new Error())},
m1(a,b){return new A.eJ("TypeError: "+A.lN(a,A.aG(b,null)))},
lN(a,b){return A.f0(a)+": type '"+A.aG(A.pL(a),null)+"' is not a subtype of type '"+b+"'"},
aQ(a,b){return new A.eJ("TypeError: "+A.lN(a,b))},
pi(a){var t=this
return t.x.b(a)||A.kl(v.typeUniverse,t).b(a)},
pn(a){return a!=null},
j0(a){if(a!=null)return a
throw A.a9(A.aQ(a,"Object"),new Error())},
pr(a){return!0},
p0(a){return a},
m6(a){return!1},
kx(a){return!0===a||!1===a},
oV(a){if(!0===a)return!0
if(!1===a)return!1
throw A.a9(A.aQ(a,"bool"),new Error())},
oW(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.a9(A.aQ(a,"bool?"),new Error())},
m0(a){if(typeof a=="number")return a
throw A.a9(A.aQ(a,"double"),new Error())},
oX(a){if(typeof a=="number")return a
if(a==null)return a
throw A.a9(A.aQ(a,"double?"),new Error())},
j3(a){return typeof a=="number"&&Math.floor(a)===a},
u(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.a9(A.aQ(a,"int"),new Error())},
oY(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.a9(A.aQ(a,"int?"),new Error())},
pm(a){return typeof a=="number"},
bK(a){if(typeof a=="number")return a
throw A.a9(A.aQ(a,"num"),new Error())},
Q(a){if(typeof a=="number")return a
if(a==null)return a
throw A.a9(A.aQ(a,"num?"),new Error())},
pp(a){return typeof a=="string"},
b0(a){if(typeof a=="string")return a
throw A.a9(A.aQ(a,"String"),new Error())},
ku(a){if(typeof a=="string")return a
if(a==null)return a
throw A.a9(A.aQ(a,"String?"),new Error())},
oZ(a){if(A.m5(a))return a
throw A.a9(A.aQ(a,"JSObject"),new Error())},
p_(a){if(a==null)return a
if(A.m5(a))return a
throw A.a9(A.aQ(a,"JSObject?"),new Error())},
mb(a,b){var t,s,r
for(t="",s="",r=0;r<a.length;++r,s=", ")t+=s+A.aG(a[r],b)
return t},
pB(a,b){var t,s,r,q,p,o,n=a.x,m=a.y
if(""===n)return"("+A.mb(m,b)+")"
t=m.length
s=n.split(",")
r=s.length-t
for(q="(",p="",o=0;o<t;++o,p=", "){q+=p
if(r===0)q+="{"
q+=A.aG(m[o],b)
if(r>=0)q+=" "+s[r];++r}return q+"})"},
m3(a2,a3,a4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=", ",a1=null
if(a4!=null){t=a4.length
if(a3==null)a3=A.j([],u.s)
else a1=a3.length
s=a3.length
for(r=t;r>0;--r)B.c.A(a3,"T"+(s+r))
for(q=u.X,p="<",o="",r=0;r<t;++r,o=a0){n=a3.length
m=n-1-r
if(!(m>=0))return A.a(a3,m)
p=p+o+a3[m]
l=a4[r]
k=l.w
if(!(k===2||k===3||k===4||k===5||l===q))p+=" extends "+A.aG(l,a3)}p+=">"}else p=""
q=a2.x
j=a2.y
i=j.a
h=i.length
g=j.b
f=g.length
e=j.c
d=e.length
c=A.aG(q,a3)
for(b="",a="",r=0;r<h;++r,a=a0)b+=a+A.aG(i[r],a3)
if(f>0){b+=a+"["
for(a="",r=0;r<f;++r,a=a0)b+=a+A.aG(g[r],a3)
b+="]"}if(d>0){b+=a+"{"
for(a="",r=0;r<d;r+=3,a=a0){b+=a
if(e[r+1])b+="required "
b+=A.aG(e[r+2],a3)+" "+e[r]}b+="}"}if(a1!=null){a3.toString
a3.length=a1}return p+"("+b+") => "+c},
aG(a,b){var t,s,r,q,p,o,n,m=a.w
if(m===5)return"erased"
if(m===2)return"dynamic"
if(m===3)return"void"
if(m===1)return"Never"
if(m===4)return"any"
if(m===6){t=a.x
s=A.aG(t,b)
r=t.w
return(r===11||r===12?"("+s+")":s)+"?"}if(m===7)return"FutureOr<"+A.aG(a.x,b)+">"
if(m===8){q=A.pP(a.x)
p=a.y
return p.length>0?q+("<"+A.mb(p,b)+">"):q}if(m===10)return A.pB(a,b)
if(m===11)return A.m3(a,b,null)
if(m===12)return A.m3(a.x,b,a.y)
if(m===13){o=a.x
n=b.length
o=n-1-o
if(!(o>=0&&o<n))return A.a(b,o)
return b[o]}return"?"},
pP(a){var t=v.mangledGlobalNames[a]
if(t!=null)return t
return"minified:"+a},
oR(a,b){var t=a.tR[b]
while(typeof t=="string")t=a.tR[t]
return t},
oQ(a,b){var t,s,r,q,p,o=a.eT,n=o[b]
if(n==null)return A.iT(a,b,!1)
else if(typeof n=="number"){t=n
s=A.eM(a,5,"#")
r=A.iZ(t)
for(q=0;q<t;++q)r[q]=s
p=A.eL(a,b,r)
o[b]=p
return p}else return n},
oO(a,b){return A.lY(a.tR,b)},
oN(a,b){return A.lY(a.eT,b)},
iT(a,b,c){var t,s=a.eC,r=s.get(b)
if(r!=null)return r
t=A.lR(A.lP(a,null,b,!1))
s.set(b,t)
return t},
iU(a,b,c){var t,s,r=b.z
if(r==null)r=b.z=new Map()
t=r.get(c)
if(t!=null)return t
s=A.lR(A.lP(a,b,c,!0))
r.set(c,s)
return s},
oP(a,b,c){var t,s,r,q=b.Q
if(q==null)q=b.Q=new Map()
t=c.as
s=q.get(t)
if(s!=null)return s
r=A.ks(a,b,c.w===9?c.y:[c])
q.set(t,r)
return r},
bJ(a,b){b.a=A.pd
b.b=A.pe
return b},
eM(a,b,c){var t,s,r=a.eC.get(c)
if(r!=null)return r
t=new A.b_(null,null)
t.w=b
t.as=c
s=A.bJ(a,t)
a.eC.set(c,s)
return s},
lV(a,b,c){var t,s=b.as+"?",r=a.eC.get(s)
if(r!=null)return r
t=A.oL(a,b,s,c)
a.eC.set(s,t)
return t},
oL(a,b,c,d){var t,s,r
if(d){t=b.w
s=!0
if(!A.cw(b))if(!(b===u.a||b===u.u))if(t!==6)s=t===7&&A.dk(b.x)
if(s)return b
else if(t===1)return u.a}r=new A.b_(null,null)
r.w=6
r.x=b
r.as=c
return A.bJ(a,r)},
lU(a,b,c){var t,s=b.as+"/",r=a.eC.get(s)
if(r!=null)return r
t=A.oJ(a,b,s,c)
a.eC.set(s,t)
return t},
oJ(a,b,c,d){var t,s
if(d){t=b.w
if(A.cw(b)||b===u.K)return b
else if(t===1)return A.eL(a,"l3",[b])
else if(b===u.a||b===u.u)return u.eH}s=new A.b_(null,null)
s.w=7
s.x=b
s.as=c
return A.bJ(a,s)},
oM(a,b){var t,s,r=""+b+"^",q=a.eC.get(r)
if(q!=null)return q
t=new A.b_(null,null)
t.w=13
t.x=b
t.as=r
s=A.bJ(a,t)
a.eC.set(r,s)
return s},
eK(a){var t,s,r,q=a.length
for(t="",s="",r=0;r<q;++r,s=",")t+=s+a[r].as
return t},
oI(a){var t,s,r,q,p,o=a.length
for(t="",s="",r=0;r<o;r+=3,s=","){q=a[r]
p=a[r+1]?"!":":"
t+=s+q+p+a[r+2].as}return t},
eL(a,b,c){var t,s,r,q=b
if(c.length>0)q+="<"+A.eK(c)+">"
t=a.eC.get(q)
if(t!=null)return t
s=new A.b_(null,null)
s.w=8
s.x=b
s.y=c
if(c.length>0)s.c=c[0]
s.as=q
r=A.bJ(a,s)
a.eC.set(q,r)
return r},
ks(a,b,c){var t,s,r,q,p,o
if(b.w===9){t=b.x
s=b.y.concat(c)}else{s=c
t=b}r=t.as+(";<"+A.eK(s)+">")
q=a.eC.get(r)
if(q!=null)return q
p=new A.b_(null,null)
p.w=9
p.x=t
p.y=s
p.as=r
o=A.bJ(a,p)
a.eC.set(r,o)
return o},
lW(a,b,c){var t,s,r="+"+(b+"("+A.eK(c)+")"),q=a.eC.get(r)
if(q!=null)return q
t=new A.b_(null,null)
t.w=10
t.x=b
t.y=c
t.as=r
s=A.bJ(a,t)
a.eC.set(r,s)
return s},
lT(a,b,c){var t,s,r,q,p,o=b.as,n=c.a,m=n.length,l=c.b,k=l.length,j=c.c,i=j.length,h="("+A.eK(n)
if(k>0){t=m>0?",":""
h+=t+"["+A.eK(l)+"]"}if(i>0){t=m>0?",":""
h+=t+"{"+A.oI(j)+"}"}s=o+(h+")")
r=a.eC.get(s)
if(r!=null)return r
q=new A.b_(null,null)
q.w=11
q.x=b
q.y=c
q.as=s
p=A.bJ(a,q)
a.eC.set(s,p)
return p},
kt(a,b,c,d){var t,s=b.as+("<"+A.eK(c)+">"),r=a.eC.get(s)
if(r!=null)return r
t=A.oK(a,b,c,s,d)
a.eC.set(s,t)
return t},
oK(a,b,c,d,e){var t,s,r,q,p,o,n,m
if(e){t=c.length
s=A.iZ(t)
for(r=0,q=0;q<t;++q){p=c[q]
if(p.w===1){s[q]=p;++r}}if(r>0){o=A.ct(a,b,s,0)
n=A.di(a,c,s,0)
return A.kt(a,o,n,c!==n)}}m=new A.b_(null,null)
m.w=12
m.x=b
m.y=c
m.as=d
return A.bJ(a,m)},
lP(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
lR(a){var t,s,r,q,p,o,n,m=a.r,l=a.s
for(t=m.length,s=0;s<t;){r=m.charCodeAt(s)
if(r>=48&&r<=57)s=A.oD(s+1,r,m,l)
else if((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124)s=A.lQ(a,s,m,l,!1)
else if(r===46)s=A.lQ(a,s,m,l,!0)
else{++s
switch(r){case 44:break
case 58:l.push(!1)
break
case 33:l.push(!0)
break
case 59:l.push(A.cs(a.u,a.e,l.pop()))
break
case 94:l.push(A.oM(a.u,l.pop()))
break
case 35:l.push(A.eM(a.u,5,"#"))
break
case 64:l.push(A.eM(a.u,2,"@"))
break
case 126:l.push(A.eM(a.u,3,"~"))
break
case 60:l.push(a.p)
a.p=l.length
break
case 62:A.oF(a,l)
break
case 38:A.oE(a,l)
break
case 63:q=a.u
l.push(A.lV(q,A.cs(q,a.e,l.pop()),a.n))
break
case 47:q=a.u
l.push(A.lU(q,A.cs(q,a.e,l.pop()),a.n))
break
case 40:l.push(-3)
l.push(a.p)
a.p=l.length
break
case 41:A.oC(a,l)
break
case 91:l.push(a.p)
a.p=l.length
break
case 93:p=l.splice(a.p)
A.lS(a.u,a.e,p)
a.p=l.pop()
l.push(p)
l.push(-1)
break
case 123:l.push(a.p)
a.p=l.length
break
case 125:p=l.splice(a.p)
A.oH(a.u,a.e,p)
a.p=l.pop()
l.push(p)
l.push(-2)
break
case 43:o=m.indexOf("(",s)
l.push(m.substring(s,o))
l.push(-4)
l.push(a.p)
a.p=l.length
s=o+1
break
default:throw"Bad character "+r}}}n=l.pop()
return A.cs(a.u,a.e,n)},
oD(a,b,c,d){var t,s,r=b-48
for(t=c.length;a<t;++a){s=c.charCodeAt(a)
if(!(s>=48&&s<=57))break
r=r*10+(s-48)}d.push(r)
return a},
lQ(a,b,c,d,e){var t,s,r,q,p,o,n=b+1
for(t=c.length;n<t;++n){s=c.charCodeAt(n)
if(s===46){if(e)break
e=!0}else{if(!((((s|32)>>>0)-97&65535)<26||s===95||s===36||s===124))r=s>=48&&s<=57
else r=!0
if(!r)break}}q=c.substring(b,n)
if(e){t=a.u
p=a.e
if(p.w===9)p=p.x
o=A.oR(t,p.x)[q]
if(o==null)A.aA('No "'+q+'" in "'+A.nJ(p)+'"')
d.push(A.iU(t,p,o))}else d.push(q)
return n},
oF(a,b){var t,s=a.u,r=A.lO(a,b),q=b.pop()
if(typeof q=="string")b.push(A.eL(s,q,r))
else{t=A.cs(s,a.e,q)
switch(t.w){case 11:b.push(A.kt(s,t,r,a.n))
break
default:b.push(A.ks(s,t,r))
break}}},
oC(a,b){var t,s,r,q=a.u,p=b.pop(),o=null,n=null
if(typeof p=="number")switch(p){case-1:o=b.pop()
break
case-2:n=b.pop()
break
default:b.push(p)
break}else b.push(p)
t=A.lO(a,b)
p=b.pop()
switch(p){case-3:p=b.pop()
if(o==null)o=q.sEA
if(n==null)n=q.sEA
s=A.cs(q,a.e,p)
r=new A.hd()
r.a=t
r.b=o
r.c=n
b.push(A.lT(q,s,r))
return
case-4:b.push(A.lW(q,b.pop(),t))
return
default:throw A.f(A.eP("Unexpected state under `()`: "+A.z(p)))}},
oE(a,b){var t=b.pop()
if(0===t){b.push(A.eM(a.u,1,"0&"))
return}if(1===t){b.push(A.eM(a.u,4,"1&"))
return}throw A.f(A.eP("Unexpected extended operation "+A.z(t)))},
lO(a,b){var t=b.splice(a.p)
A.lS(a.u,a.e,t)
a.p=b.pop()
return t},
cs(a,b,c){if(typeof c=="string")return A.eL(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.oG(a,b,c)}else return c},
lS(a,b,c){var t,s=c.length
for(t=0;t<s;++t)c[t]=A.cs(a,b,c[t])},
oH(a,b,c){var t,s=c.length
for(t=2;t<s;t+=3)c[t]=A.cs(a,b,c[t])},
oG(a,b,c){var t,s,r=b.w
if(r===9){if(c===0)return b.x
t=b.y
s=t.length
if(c<=s)return t[c-1]
c-=s
b=b.x
r=b.w}else if(c===0)return b
if(r!==8)throw A.f(A.eP("Indexed base must be an interface type"))
t=b.y
if(c<=t.length)return t[c-1]
throw A.f(A.eP("Bad index "+c+" for "+b.D(0)))},
qe(a,b,c){var t,s=b.d
if(s==null)s=b.d=new Map()
t=s.get(c)
if(t==null){t=A.a6(a,b,null,c,null)
s.set(c,t)}return t},
a6(a,b,c,d,e){var t,s,r,q,p,o,n,m,l,k,j
if(b===d)return!0
if(A.cw(d))return!0
t=b.w
if(t===4)return!0
if(A.cw(b))return!1
if(b.w===1)return!0
s=t===13
if(s)if(A.a6(a,c[b.x],c,d,e))return!0
r=d.w
q=u.a
if(b===q||b===u.u){if(r===7)return A.a6(a,b,c,d.x,e)
return d===q||d===u.u||r===6}if(d===u.K){if(t===7)return A.a6(a,b.x,c,d,e)
return t!==6}if(t===7){if(!A.a6(a,b.x,c,d,e))return!1
return A.a6(a,A.kl(a,b),c,d,e)}if(t===6)return A.a6(a,q,c,d,e)&&A.a6(a,b.x,c,d,e)
if(r===7){if(A.a6(a,b,c,d.x,e))return!0
return A.a6(a,b,c,A.kl(a,d),e)}if(r===6)return A.a6(a,b,c,q,e)||A.a6(a,b,c,d.x,e)
if(s)return!1
q=t!==11
if((!q||t===12)&&d===u.Z)return!0
p=t===10
if(p&&d===u.gT)return!0
if(r===12){if(b===u.U)return!0
if(t!==12)return!1
o=b.y
n=d.y
m=o.length
if(m!==n.length)return!1
c=c==null?o:o.concat(c)
e=e==null?n:n.concat(e)
for(l=0;l<m;++l){k=o[l]
j=n[l]
if(!A.a6(a,k,c,j,e)||!A.a6(a,j,e,k,c))return!1}return A.m4(a,b.x,c,d.x,e)}if(r===11){if(b===u.U)return!0
if(q)return!1
return A.m4(a,b,c,d,e)}if(t===8){if(r!==8)return!1
return A.pj(a,b,c,d,e)}if(p&&r===10)return A.po(a,b,c,d,e)
return!1},
m4(a2,a3,a4,a5,a6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1
if(!A.a6(a2,a3.x,a4,a5.x,a6))return!1
t=a3.y
s=a5.y
r=t.a
q=s.a
p=r.length
o=q.length
if(p>o)return!1
n=o-p
m=t.b
l=s.b
k=m.length
j=l.length
if(p+k<o+j)return!1
for(i=0;i<p;++i){h=r[i]
if(!A.a6(a2,q[i],a6,h,a4))return!1}for(i=0;i<n;++i){h=m[i]
if(!A.a6(a2,q[p+i],a6,h,a4))return!1}for(i=0;i<j;++i){h=m[n+i]
if(!A.a6(a2,l[i],a6,h,a4))return!1}g=t.c
f=s.c
e=g.length
d=f.length
for(c=0,b=0;b<d;b+=3){a=f[b]
for(;;){if(c>=e)return!1
a0=g[c]
c+=3
if(a<a0)return!1
a1=g[c-2]
if(a0<a){if(a1)return!1
continue}h=f[b+1]
if(a1&&!h)return!1
h=g[c-1]
if(!A.a6(a2,f[b+2],a6,h,a4))return!1
break}}while(c<e){if(g[c+1])return!1
c+=3}return!0},
pj(a,b,c,d,e){var t,s,r,q,p,o=b.x,n=d.x
while(o!==n){t=a.tR[o]
if(t==null)return!1
if(typeof t=="string"){o=t
continue}s=t[n]
if(s==null)return!1
r=s.length
q=r>0?new Array(r):v.typeUniverse.sEA
for(p=0;p<r;++p)q[p]=A.iU(a,b,s[p])
return A.lZ(a,q,null,c,d.y,e)}return A.lZ(a,b.y,null,c,d.y,e)},
lZ(a,b,c,d,e,f){var t,s=b.length
for(t=0;t<s;++t)if(!A.a6(a,b[t],d,e[t],f))return!1
return!0},
po(a,b,c,d,e){var t,s=b.y,r=d.y,q=s.length
if(q!==r.length)return!1
if(b.x!==d.x)return!1
for(t=0;t<q;++t)if(!A.a6(a,s[t],c,r[t],e))return!1
return!0},
dk(a){var t=a.w,s=!0
if(!(a===u.a||a===u.u))if(!A.cw(a))if(t!==6)s=t===7&&A.dk(a.x)
return s},
cw(a){var t=a.w
return t===2||t===3||t===4||t===5||a===u.X},
lY(a,b){var t,s,r=Object.keys(b),q=r.length
for(t=0;t<q;++t){s=r[t]
a[s]=b[s]}},
iZ(a){return a>0?new Array(a):v.typeUniverse.sEA},
b_:function b_(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
hd:function hd(){this.c=this.b=this.a=null},
hh:function hh(a){this.a=a},
hb:function hb(){},
eJ:function eJ(a){this.a=a},
nn(a,b){return new A.aV(a.v("@<0>").bJ(b).v("aV<1,2>"))},
aD(a,b,c){return b.v("@<0>").bJ(c).v("k2<1,2>").a(A.mg(a,new A.aV(b.v("@<0>").bJ(c).v("aV<1,2>"))))},
D(a,b){return new A.aV(a.v("@<0>").bJ(b).v("aV<1,2>"))},
no(a){return new A.cr(a.v("cr<0>"))},
lr(a){return new A.cr(a.v("cr<0>"))},
kr(){var t=Object.create(null)
t["<non-identifier-key>"]=t
delete t["<non-identifier-key>"]
return t},
b3(a,b,c){var t=A.nn(b,c)
a.aT(0,new A.i0(t,b,c))
return t},
k3(a){var t,s
if(A.kC(a))return"{...}"
t=new A.cm("")
try{s={}
B.c.A($.aH,a)
t.a+="{"
s.a=!0
a.aT(0,new A.i2(s,t))
t.a+="}"}finally{if(0>=$.aH.length)return A.a($.aH,-1)
$.aH.pop()}s=t.a
return s.charCodeAt(0)==0?s:s},
cr:function cr(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
hg:function hg(a){this.a=a
this.b=null},
eC:function eC(a,b,c){var _=this
_.a=a
_.b=b
_.d=_.c=null
_.$ti=c},
i0:function i0(a,b,c){this.a=a
this.b=b
this.c=c},
F:function F(){},
ai:function ai(){},
i2:function i2(a,b){this.a=a
this.b=b},
bG:function bG(){},
eI:function eI(){},
px(a,b){var t,s,r,q=null
try{q=JSON.parse(a)}catch(s){t=A.kH(s)
r=A.hD(String(t),null,null)
throw A.f(r)}r=A.j1(q)
return r},
j1(a){var t
if(a==null)return null
if(typeof a!="object")return a
if(!Array.isArray(a))return new A.he(a,Object.create(null))
for(t=0;t<a.length;++t)a[t]=A.j1(a[t])
return a},
oT(a,b,c){var t,s,r,q,p=c-b
if(p<=4096)t=$.mF()
else t=new Uint8Array(p)
for(s=0;s<p;++s){r=b+s
if(!(r<a.length))return A.a(a,r)
q=a[r]
if((q&255)!==q)q=255
t[s]=q}return t},
oS(a,b,c,d){var t=a?$.mE():$.mD()
if(t==null)return null
if(0===c&&d===b.length)return A.lX(t,b)
return A.lX(t,b.subarray(c,d))},
lX(a,b){var t,s
try{t=a.decode(b)
return t}catch(s){}return null},
lp(a,b,c){return new A.dQ(a,b)},
p5(a){return a.jP()},
oA(a,b){return new A.iO(a,[],A.pW())},
oB(a,b,c){var t,s=new A.cm(""),r=A.oA(s,b)
r.d8(a)
t=s.a
return t.charCodeAt(0)==0?t:t},
oU(a){switch(a){case 65:return"Missing extension byte"
case 67:return"Unexpected extension byte"
case 69:return"Invalid UTF-8 byte"
case 71:return"Overlong encoding"
case 73:return"Out of unicode range"
case 75:return"Encoded surrogate"
case 77:return"Unfinished UTF-8 octet sequence"
default:return""}},
he:function he(a,b){this.a=a
this.b=b
this.c=null},
hf:function hf(a){this.a=a},
iX:function iX(){},
iW:function iW(){},
iS:function iS(){},
bS:function bS(){},
eZ:function eZ(){},
f_:function f_(){},
dQ:function dQ(a,b){this.a=a
this.b=b},
fD:function fD(a,b){this.a=a
this.b=b},
fC:function fC(){},
hY:function hY(a){this.b=a},
hX:function hX(a){this.a=a},
iP:function iP(){},
iQ:function iQ(a,b){this.a=a
this.b=b},
iO:function iO(a,b,c){this.c=a
this.a=b
this.b=c},
fE:function fE(){},
hZ:function hZ(a){this.a=a},
h5:function h5(){},
ip:function ip(){},
iY:function iY(a){this.b=0
this.c=a},
h6:function h6(a){this.a=a},
hi:function hi(a){this.a=a
this.b=16
this.c=0},
qc(a){var t=A.nD(a,null)
if(t!=null)return t
throw A.f(A.hD(a,null,null))},
P(a,b,c,d){var t,s=J.lk(a,d)
if(a!==0&&b!=null)for(t=0;t<a;++t)s[t]=b
return s},
ls(a,b){var t,s,r=A.j([],b.v("r<0>"))
for(t=a.length,s=0;s<a.length;a.length===t||(0,A.a_)(a),++s)B.c.A(r,b.a(a[s]))
return r},
q(a,b){var t,s
if(Array.isArray(a))return A.j(a.slice(0),b.v("r<0>"))
t=A.j([],b.v("r<0>"))
for(s=J.bu(a);s.F();)B.c.A(t,s.gM())
return t},
lt(a,b,c){var t,s=J.k_(a,c)
for(t=0;t<a;++t)B.c.i(s,t,b.$1(t))
return s},
en(a,b,c){var t,s,r,q,p
A.d8(b,"start")
t=c==null
s=!t
if(s){r=c-b
if(r<0)throw A.f(A.ak(c,b,null,"end",null))
if(r===0)return""}if(Array.isArray(a)){q=a
p=q.length
if(t)c=p
return A.lB(b>0||c<p?q.slice(b,c):q)}if(u.e.b(a))return A.nM(a,b,c)
if(s)a=J.mR(a,c)
if(b>0)a=J.jM(a,b)
t=A.q(a,u.p)
return A.lB(t)},
nM(a,b,c){var t=a.length
if(b>=t)return""
return A.nG(a,b,c==null||c>t?t:c)},
lG(a,b,c){var t=J.bu(b)
if(!t.F())return a
if(c.length===0){do a+=A.z(t.gM())
while(t.F())}else{a+=A.z(t.gM())
while(t.F())a=a+c+A.z(t.gM())}return a},
f0(a){if(typeof a=="number"||A.kx(a)||a==null)return J.ac(a)
if(typeof a=="string")return JSON.stringify(a)
return A.nE(a)},
eP(a){return new A.eO(a)},
bQ(a){return new A.bb(!1,null,null,a)},
nI(a){var t=null
return new A.d7(t,t,!1,t,t,a)},
lE(a,b){return new A.d7(null,null,!0,a,b,"Value not in range")},
ak(a,b,c,d,e){return new A.d7(b,c,!0,a,d,"Invalid value")},
aZ(a,b,c){if(0>a||a>c)throw A.f(A.ak(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.f(A.ak(b,a,c,"end",null))
return b}return c},
d8(a,b){if(a<0)throw A.f(A.ak(a,0,null,b,null))
return a},
jV(a,b,c,d){return new A.fh(b,!0,a,d,"Index out of range")},
b5(a){return new A.es(a)},
lJ(a){return new A.h3(a)},
nK(a){return new A.da(a)},
b2(a){return new A.eX(a)},
hD(a,b,c){return new A.hC(a,b,c)},
nj(a,b,c){var t,s
if(A.kC(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}t=A.j([],u.s)
B.c.A($.aH,a)
try{A.ps(a,t)}finally{if(0>=$.aH.length)return A.a($.aH,-1)
$.aH.pop()}s=A.lG(b,u.hf.a(t),", ")+c
return s.charCodeAt(0)==0?s:s},
jZ(a,b,c){var t,s
if(A.kC(a))return b+"..."+c
t=new A.cm(b)
B.c.A($.aH,a)
try{s=t
s.a=A.lG(s.a,a,", ")}finally{if(0>=$.aH.length)return A.a($.aH,-1)
$.aH.pop()}t.a+=c
s=t.a
return s.charCodeAt(0)==0?s:s},
ps(a,b){var t,s,r,q,p,o,n,m=a.gI(a),l=0,k=0
for(;;){if(!(l<80||k<3))break
if(!m.F())return
t=A.z(m.gM())
B.c.A(b,t)
l+=t.length+2;++k}if(!m.F()){if(k<=5)return
if(0>=b.length)return A.a(b,-1)
s=b.pop()
if(0>=b.length)return A.a(b,-1)
r=b.pop()}else{q=m.gM();++k
if(!m.F()){if(k<=4){B.c.A(b,A.z(q))
return}s=A.z(q)
if(0>=b.length)return A.a(b,-1)
r=b.pop()
l+=s.length+2}else{p=m.gM();++k
for(;m.F();q=p,p=o){o=m.gM();++k
if(k>100){for(;;){if(!(l>75&&k>3))break
if(0>=b.length)return A.a(b,-1)
l-=b.pop().length+2;--k}B.c.A(b,"...")
return}}r=A.z(q)
s=A.z(p)
l+=s.length+r.length+4}}if(k>b.length+2){l+=5
n="..."}else n=null
for(;;){if(!(l>80&&b.length>3))break
if(0>=b.length)return A.a(b,-1)
l-=b.pop().length+2
if(n==null){l+=5
n="..."}}if(n!=null)B.c.A(b,n)
B.c.A(b,r)
B.c.A(b,s)},
nB(a,b,c,d){var t
if(B.a3===c){t=B.a.gH(a)
b=B.a.gH(b)
return A.ig(A.bm(A.bm($.hr(),t),b))}if(B.a3===d){t=B.a.gH(a)
b=B.a.gH(b)
c=J.bP(c)
return A.ig(A.bm(A.bm(A.bm($.hr(),t),b),c))}t=B.a.gH(a)
b=B.a.gH(b)
c=J.bP(c)
d=J.bP(d)
d=A.ig(A.bm(A.bm(A.bm(A.bm($.hr(),t),b),c),d))
return d},
m(a){var t,s,r=$.hr()
for(t=a.length,s=0;s<a.length;a.length===t||(0,A.a_)(a),++s)r=A.bm(r,J.bP(a[s]))
return A.ig(r)},
iJ:function iJ(){},
T:function T(){},
eO:function eO(a){this.a=a},
er:function er(){},
bb:function bb(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
d7:function d7(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
fh:function fh(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
es:function es(a){this.a=a},
h3:function h3(a){this.a=a},
da:function da(a){this.a=a},
eX:function eX(a){this.a=a},
fF:function fF(){},
em:function em(){},
iK:function iK(a){this.a=a},
hC:function hC(a,b,c){this.a=a
this.b=b
this.c=c},
e:function e(){},
e1:function e1(){},
H:function H(){},
cm:function cm(a){this.a=a},
f7(a){return new A.a7(a)},
m8(a){var t,s,r,q,p,o,n,m,l,k,j=a.length
if(j<12)throw A.f(B.cX)
t=A.jO(a)
if(t.getUint32(0,!0)!==1179937895)throw A.f(B.cV)
if(t.getUint32(4,!0)!==2)throw A.f(B.cW)
if(t.getUint32(8,!0)!==j)throw A.f(B.cT)
for(s=null,r=null,q=12;p=q+8,p<=j;){o=t.getUint32(q,!0)
n=t.getUint32(q+4,!0)
m=p+o
if(m>j)throw A.f(B.d_)
l=A.io(a,p,m)
if(n===1313821514)s=s==null?l:s
if(n===5130562)r=r==null?l:r
q+=8+o}if(s==null)throw A.f(B.cR)
k=B.K.f0(B.aQ.f_(s,!0),null)
if(!u.f.b(k))throw A.f(B.d2)
j=A.b3(k,u.N,u.z)
if(r==null)p=new Uint8Array(0)
else p=r
return new A.iM(j,p)},
pC(a){var t,s,r=u.N,q=J.ba(a.bc("extensionsUsed"),new A.jd(),r),p=A.no(r)
p.bD(0,q)
p.bD(0,J.ba(a.bc("extensionsRequired"),new A.je(),r))
r=A.l(p)
q=r.v("bs<1>")
t=A.q(new A.bs(p,r.v("a3(1)").a(B.c6.giX(B.c6)),q),q.v("e.E"))
if(t.length!==0)throw A.f(A.f7(B.c.c9(t,", ")+' cannot be undone offline \u2014 re-export the model uncompressed ("Export \u2192 Compression: off", guide \xa7C8)'))
for(r=J.bu(a.bc("images")),q=u.f;r.F();){p=q.a(r.gM()).k(0,"mimeType")
s=p==null?null:J.ac(p)
if(s==null)s=""
if(B.p.aR(s,"ktx")||B.p.aR(s,"basis"))throw A.f(B.cS)}},
ky(a,b,c){var t,s,r,q,p,o,n,m,l,k,j,i=null,h="byteOffset",g=a.b_("accessors",b),f=A.Q(g.k(0,"componentType")),e=f==null?i:B.b.h(f)
if(e==null)e=5126
if(e!==5126)throw A.f(A.f7("an attribute uses componentType "+e+" (quantised), which this tool does not rewrite \u2014 export without KHR_mesh_quantization (guide \xa7C8)"))
f=A.Q(g.k(0,"count"))
t=f==null?i:B.b.h(f)
if(t==null)t=0
f=A.Q(g.k(0,"bufferView"))
f=f==null?i:B.b.h(f)
s=a.b_("bufferViews",f==null?-1:f)
f=A.Q(s.k(0,"byteStride"))
r=f==null?i:B.b.h(f)
f=A.Q(s.k(0,h))
f=f==null?i:B.b.h(f)
if(f==null)f=0
q=A.Q(g.k(0,h))
q=q==null?i:B.b.h(q)
p=f+(q==null?0:q)
o=4*c
n=r==null?o:r
m=A.jO(a.b)
l=A.P(t*c,0,!1,u.i)
for(k=0;k<t;++k)for(f=k*c,q=p+k*n,j=0;j<c;++j)B.c.i(l,f+j,m.getFloat32(q+j*4,!0))
return l},
py(a,b,c){var t,s,r,q,p,o,n,m,l=null,k="byteOffset",j=a.b_("accessors",b),i=A.Q(j.k(0,"count")),h=i==null?l:B.b.h(i)
if(h==null)h=0
i=A.Q(j.k(0,"componentType"))
t=i==null?l:B.b.h(i)
if(t==null)t=5123
i=A.Q(j.k(0,"bufferView"))
i=i==null?l:B.b.h(i)
i=A.Q(a.b_("bufferViews",i==null?-1:i).k(0,k))
i=i==null?l:B.b.h(i)
if(i==null)i=0
s=A.Q(j.k(0,k))
s=s==null?l:B.b.h(s)
r=i+(s==null?0:s)
q=A.jO(a.b)
p=A.P(h,0,!1,u.p)
for(i=5125===t,s=5123===t,o=5121===t,n=0;n<h;++n){A:{if(o){m=q.getUint8(r+n)
break A}if(s){m=q.getUint16(r+n*2,!0)
break A}if(i){m=q.getUint32(r+n*4,!0)
break A}m=0
break A}B.c.i(p,n,m)}if(c>0&&B.c.eN(p,new A.j9(c)))throw A.f(B.cQ)
return p},
ma(b7,b8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4=null,b5=u.s,b6=A.j([],b5)
for(t=J.bu(b7.bc("materials")),s=u.f;t.F();){r=s.a(t.gM()).k(0,"name")
B.c.A(b6,J.ac(r==null?"":r))}t=u.n
q=A.j([],t)
p=A.j([],t)
o=A.j([],t)
r=u.t
n=A.j([],r)
m=A.j([],r)
for(l=J.bu(b7.bc("meshes")),k=u.Y,j=u.i,i=u.j,h=!0,g=!0;l.F();){f=s.a(l.gM()).k(0,"primitives")
e=J.bu(i.b(f)?f:B.J)
while(e.F()){d=s.a(e.gM())
c=k.a(d.k(0,"attributes"))
if(c==null)c=B.jW
b=A.Q(c.k(0,"POSITION"))
a=b==null?b4:B.b.h(b)
if(a==null)throw A.f(B.cZ)
b=A.Q(d.k(0,"mode"))
a0=b==null?b4:B.b.h(b)
if(a0==null)a0=4
if(a0!==4)throw A.f(A.f7("a primitive uses draw mode "+a0+"; only triangles can be normalised"))
a1=q.length/3|0
b=A.Q(b7.b_("accessors",a).k(0,"count"))
a2=b==null?b4:B.b.h(b)
if(a2==null)a2=0
B.c.bD(q,A.ky(b7,a,3))
b=A.Q(c.k(0,"NORMAL"))
a3=b==null?b4:B.b.h(b)
if(a3==null){B.c.bD(p,A.P(a2*3,0,!1,j))
h=!1}else B.c.bD(p,A.ky(b7,a3,3))
b=A.Q(c.k(0,"TEXCOORD_0"))
a4=b==null?b4:B.b.h(b)
if(a4==null){B.c.bD(o,A.P(a2*2,0,!1,j))
g=!1}else B.c.bD(o,A.ky(b7,a4,2))
b=A.Q(d.k(0,"indices"))
a5=b==null?b4:B.b.h(b)
if(a5==null){if(a2<0)A.aA(A.bQ("Length must be a non-negative integer: "+a2))
a6=A.j(new Array(a2),r)
for(a7=0;a7<a2;++a7)a6[a7]=a7
a8=a6}else a8=A.py(b7,a5,a2)
b=A.Q(d.k(0,"material"))
a9=b==null?b4:B.b.h(b)
if(a9==null)a9=-1
for(a7=0;b=a7+2,b0=a8.length,b<b0;a7+=3){if(!(a7<b0))return A.a(a8,a7)
B.c.A(n,a1+a8[a7])
b0=a7+1
if(!(b0<a8.length))return A.a(a8,b0)
B.c.A(n,a1+a8[b0])
if(!(b<a8.length))return A.a(a8,b)
B.c.A(n,a1+a8[b])
B.c.A(m,a9)}}}if(n.length===0)throw A.f(B.d1)
if(!h)B.c.A(b8,"note: the mesh has no normals; the renderer will light it flat")
if(!g)B.c.A(b8,"note: the mesh has no UVs, so any texture map has nothing to sample")
b1=A.j([],b5)
for(b5=b7.a,b2=0;b2<4;++b2){b3=B.ff[b2]
if(J.kR(i.b(b5.k(0,b3))?i.a(b5.k(0,b3)):B.J))B.c.A(b1,b3)}if(b1.length!==0)B.c.A(b8,"dropped "+B.c.c9(b1,", ")+" \u2014 a try-on model carries only the shoe")
b5=h?p:A.j([],t)
return new A.iL(q,b5,g?o:A.j([],t),n,m,b6)},
pt(a,b){var t,s,r,q,p,o,n,m,l,k,j=A.P(12,0,!1,u.i)
for(t=0;t<3;++t){for(s=t*3,r=0;r<3;++r){for(q=0,p=0;p<3;++p){o=s+p
if(!(o<12))return A.a(a,o)
o=a[o]
n=p*3+r
if(!(n<12))return A.a(b,n)
q+=o*b[n]}B.c.i(j,s+r,q)}o=9+t
if(!(s<12))return A.a(a,s)
n=a[s]
m=b[9]
l=s+1
if(!(l<12))return A.a(a,l)
l=a[l]
k=b[10]
s+=2
if(!(s<12))return A.a(a,s)
B.c.i(j,o,n*m+l*k+a[s]*b[11]+a[o])}return j},
pv(a5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4=a5.k(0,"matrix")
if(u.j.b(a4)&&J.ao(a4)===16){t=J.ba(a4,new A.j4(),u.i)
s=A.q(t,t.$ti.v("a1.E"))
t=s.length
if(0>=t)return A.a(s,0)
r=s[0]
if(4>=t)return A.a(s,4)
q=s[4]
if(8>=t)return A.a(s,8)
p=s[8]
o=s[1]
n=s[5]
if(9>=t)return A.a(s,9)
m=s[9]
l=s[2]
k=s[6]
if(10>=t)return A.a(s,10)
j=s[10]
if(12>=t)return A.a(s,12)
i=s[12]
if(13>=t)return A.a(s,13)
h=s[13]
if(14>=t)return A.a(s,14)
return A.j([r,q,p,o,n,m,l,k,j,i,h,s[14]],u.n)}t=u.M
r=t.a(a5.k(0,"rotation"))
if(r==null)g=null
else{r=J.ba(r,new A.j5(),u.i)
r=A.q(r,r.$ti.v("a1.E"))
g=r}if(g==null)g=B.de
r=t.a(a5.k(0,"translation"))
if(r==null)f=null
else{r=J.ba(r,new A.j6(),u.i)
r=A.q(r,r.$ti.v("a1.E"))
f=r}if(f==null)f=B.dd
t=t.a(a5.k(0,"scale"))
if(t==null)e=null
else{t=J.ba(t,new A.j7(),u.i)
t=A.q(t,t.$ti.v("a1.E"))
e=t}if(e==null)e=B.dA
t=g.length
if(0>=t)return A.a(g,0)
d=g[0]
if(1>=t)return A.a(g,1)
c=g[1]
if(2>=t)return A.a(g,2)
b=g[2]
if(3>=t)return A.a(g,3)
a=g[3]
t=c*c
r=b*b
q=d*c
p=b*a
o=d*b
n=c*a
m=d*d
l=c*b
k=d*a
a0=[1-2*(t+r),2*(q-p),2*(o+n),2*(q+p),1-2*(m+r),2*(l-k),2*(o-n),2*(l+k),1-2*(m+t)]
t=a0[0]
m=e.length
if(0>=m)return A.a(e,0)
k=e[0]
l=a0[1]
if(1>=m)return A.a(e,1)
n=e[1]
o=a0[2]
if(2>=m)return A.a(e,2)
m=e[2]
r=a0[3]
p=a0[4]
q=a0[5]
j=a0[6]
i=a0[7]
h=a0[8]
a1=f.length
if(0>=a1)return A.a(f,0)
a2=f[0]
if(1>=a1)return A.a(f,1)
a3=f[1]
if(2>=a1)return A.a(f,2)
return A.j([t*k,l*n,o*m,r*k,p*n,q*m,j*k,i*n,h*m,a2,a3,f[2]],u.n)},
pI(a,b){var t,s,r,q,p,o,n,m,l,k,j,i=a.bc("nodes"),h=J.S(i)
if(h.gaU(i))return B.ah
t=a.bc("scenes")
s=A.Q(a.a.k(0,"scene"))
r=s==null?null:B.b.h(s)
if(r==null)r=J.mP(t)?-1:0
q=r>=0&&r<J.ao(t)?u.f.a(J.c(t,r)).k(0,"nodes"):null
s=u.p
if(u.j.b(q)){h=J.ba(q,new A.jf(),s)
p=A.q(h,h.$ti.v("a1.E"))}else{o=h.gt(i)
n=J.c4(o,s)
for(m=0;m<o;++m)n[m]=m
p=n}l=A.j([],u.gy)
k=new A.jh(i,l)
for(h=p.length,j=0;j<p.length;p.length===h||(0,A.a_)(p),++j)k.$2(p[j],B.ah)
h=l.length
if(h===0)return B.ah
if(h>1){if(B.c.eN(l,new A.jg(l)))throw A.f(B.cY)
B.c.A(b,"the scene has "+l.length+" identical instances of the mesh; merged into one")}return B.c.gdI(l)},
p2(a,b,c){var t,s,r=A.pI(b,c)
for(t=!1,s=0;s<12;++s)if(Math.abs(r[s]-B.ah[s])>1e-9)t=!0
if(!t)return
A.hj(a,r)
B.c.A(c,"baked the root node transform into the vertices ("+A.p6(r)+") \u2014 the validator reads accessor bounds, not the node tree")},
hj(a,b){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=a.a
for(t=0;s=g.length,t<s;t+=3){r=g[t]
q=t+1
if(!(q<s))return A.a(g,q)
p=g[q]
o=t+2
if(!(o<s))return A.a(g,o)
p=[r,p,g[o]]
r=b[0]
s=p[0]
n=b[1]
m=p[1]
l=b[2]
p=p[2]
k=[r*s+n*m+l*p+b[9],b[3]*s+b[4]*m+b[5]*p+b[10],b[6]*s+b[7]*m+b[8]*p+b[11]]
B.c.i(g,t,k[0])
B.c.i(g,q,k[1])
B.c.i(g,o,k[2])}j=a.b
for(t=0;s=j.length,t<s;t+=3){r=j[t]
q=t+1
if(!(q<s))return A.a(j,q)
p=j[q]
o=t+2
if(!(o<s))return A.a(j,o)
p=[r,p,j[o]]
r=b[0]
s=p[0]
n=b[1]
m=p[1]
l=b[2]
p=p[2]
i=[r*s+n*m+l*p,b[3]*s+b[4]*m+b[5]*p,b[6]*s+b[7]*m+b[8]*p]
p=i[0]
m=i[1]
s=i[2]
h=Math.sqrt(p*p+m*m+s*s)
if(h===0)continue
B.c.i(j,t,p/h)
B.c.i(j,q,m/h)
B.c.i(j,o,s/h)}},
p6(a){var t,s,r,q,p,o,n,m,l=A.j([],u.s)
for(t=u.n,s=0;s<3;++s){r=A.j([],t)
for(q=s*3,p=0;p<3;++p){o=q+p
if(!(o<12))return A.a(a,o)
B.c.A(r,a[o])}n=A.pu(r)
if(n!=null)B.c.A(l,"xyz"[s]+"\u2190"+n)}t=a[9]
q=a[10]
o=a[11]
m=B.c.c9(l,", ")
return m+(Math.abs(t)+Math.abs(q)+Math.abs(o)>1e-9?", translated":"")},
pu(a){var t,s,r,q,p
for(t=a.length,s=0;s<6;++s){if(0>=t)return A.a(a,0)
r=a[0]
q=B.j9[s]
p=!1
if(Math.abs(r-q[0])<0.000001){if(1>=t)return A.a(a,1)
if(Math.abs(a[1]-q[1])<0.000001){if(2>=t)return A.a(a,2)
r=Math.abs(a[2]-q[2])<0.000001}else r=p}else r=p
if(r)return B.f0[s]}return null},
pD(a,b,c){var t,s,r,q,p,o=a.d3(),n=o[3]-o[0],m=o[4]-o[1],l=o[5]-o[2]
if(m>=n&&m>=l)throw A.f(B.cU)
if(n>l){t=b.b
s=!0
switch(t){case null:case void 0:break
case B.cc:break
case B.cd:s=!1
break
case B.ce:s=A.aA(B.aV)
break
case B.aI:s=A.aA(B.aV)
break
default:s=null}if(t==null)B.c.A(c,"note: the length runs along X and no --toe was given, so the toe is assumed to be at +X; pass --toe -x if the shoe would end up backwards (the validator cannot tell, checklist \xa72)")
r=(s?-1:1)*3.141592653589793/2
q=Math.abs(Math.cos(r))<1e-12?0:Math.cos(r)
p=Math.sin(r)
A.hj(a,A.j([q,0,p,0,1,0,-p,0,q,0,0,0],u.n))
B.c.A(c,"rotated 90\xb0 about Y so the length runs along Z with the toe at +Z")
return}t=b.b
if(t==null)B.c.A(c,"note: the length already runs along Z and no --toe was given, so the toe is assumed to be at +Z (checklist \xa72)")
if(t===B.aI){A.hj(a,A.j([-1,0,0,0,1,0,0,0,-1,0,0,0],u.n))
B.c.A(c,"turned the model 180\xb0 about Y so the toe sits at +Z")}},
pH(a,b,c){var t,s,r,q=b.a
if(q==null){B.c.A(c,"note: no declared external length, so the mesh keeps its authored scale \u2014 the scale check compares it against that number and will fail until the handover supplies one (guide \xa75.1)")
return}t=a.d3()
s=(t[5]-t[2])*1000
if(s<=0)throw A.f(B.d0)
r=q/s
if(Math.abs(r-1)<1e-9)return
A.hj(a,A.j([r,0,0,0,r,0,0,0,r,0,0,0],u.n))
B.c.A(c,"scaled by "+B.b.bn(r,4)+" so the mesh measures "+B.b.bn(q,1)+" mm \u2014 it was "+B.b.bn(s,1)+" mm, "+B.b.bn(s/q,2)+"\xd7 the declaration")},
pz(b4,b5,b6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1="images",a2=null,a3="image/jpeg",a4=A.j([],u.g5),a5=u.d,a6=u.T,a7=u.I,a8=b5.e,a9=b5.d,b0=b4.b,b1=b4.a,b2=u.j,b3=0
for(;;){if(!(b3<J.ao(b2.b(b1.k(0,a1))?b2.a(b1.k(0,a1)):B.J)))break
t=b4.b_(a1,b3)
s=A.Q(t.k(0,"bufferView"))
r=s==null?a2:B.b.h(s)
if(r==null)throw A.f(A.f7("images["+b3+"] is not embedded in the .glb \u2014 export with textures embedded (guide \xa7C8)"))
q=b4.b_("bufferViews",r)
s=A.Q(q.k(0,"byteOffset"))
p=s==null?a2:B.b.h(s)
if(p==null)p=0
s=A.Q(q.k(0,"byteLength"))
o=s==null?a2:B.b.h(s)
if(o==null)o=0
n=A.io(b0,p,p+o)
m=A.q0(n)
l=m==null?a2:m.aS(n,a2)
if(l==null)throw A.f(A.f7("images["+b3+"] ("+A.z(t.k(0,"mimeType"))+") could not be decoded \u2014 re-export the textures as plain PNG or JPEG (guide \xa7C8)"))
s=l.a
k=s==null
j=k?a2:s.a
if(j==null)j=0
i=k?a2:s.b
if(i==null)i=0
h=Math.min(1,a9/Math.max(j,i))
j=k?a2:s.a
g=Math.max(1,B.b.aD((j==null?0:j)*h))
s=k?a2:s.b
f=Math.max(1,B.b.aD((s==null?0:s)*h))
e=h<1?A.pX(l,f,B.b4,g):l
s=new Uint8Array(64)
k=new Uint8Array(64)
j=new Float32Array(64)
i=new Float32Array(64)
d=A.P(65535,a2,!1,a6)
c=A.P(65535,a2,!1,a7)
b=A.P(64,a2,!1,a7)
a=A.P(64,a2,!1,a7)
s=new A.hV(s,k,j,i,d,c,b,a,new Int32Array(2048))
s.e=s.cL(B.bR,B.a7)
s.f=s.cL(B.bt,B.a7)
s.r=a5.a(s.cL(B.b9,B.bi))
s.w=a5.a(s.cL(B.bn,B.bB))
s.hT()
s.hW()
s.ft(a8)
a0=new Uint8Array(A.w(s.j8(e,B.b5)))
s=A.ji(o)
k=A.ji(a0.length)
j=t.k(0,"name")
j=A.z(j==null?"":j)
i=l.a
d=i==null
c=d?a2:i.a
if(c==null)c=0
i=d?a2:i.b
if(i==null)i=0
B.c.A(b6,"images["+b3+"] "+j+" "+c+"\xd7"+i+" \u2192 "+A.z(g)+"\xd7"+A.z(f)+" "+A.ql(a3,"image/","",0)+" "+(s+" \u2192 "+k))
s=t.k(0,"name")
B.c.A(a4,new A.ha(s==null?a2:J.ac(s),a3,a0));++b3}return a4},
pA(a9,b0,b1,b2){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0="materials",a1=null,a2="name",a3=u.s,a4=A.j([],a3),a5=b1.f,a6=a9.a,a7=u.j,a8=0
for(;;){if(!(a8<J.ao(a7.b(a6.k(0,a0))?a7.a(a6.k(0,a0)):B.J)))break
t=a9.b_(a0,a8).k(0,a2)
s=t==null?a1:J.ac(t)
if(s==null)s=""
if(s.length===0)s="upper"
t=a5.k(0,s)
B.c.A(a4,t==null?s:t);++a8}a5=u.N
r=A.D(a5,u.E)
q=new A.ja(a4,b1,r)
p=b1.r
if(p!=null){o=p/1000
a3=b0.f
a5=a3.length===0?-1:0
a6=u.t
a7=A.j([],a6)
n=new A.aF("sole",a5,a7)
a3=a3.length===0?-1:0
a6=A.j([],a6)
m=new A.aF("upper",a3,a6)
for(a3=b0.d,a5=b0.a,l=0;t=a3.length,l<(t/3|0);++l){for(k=a5.length,j=l*3,i=!0,h=0;h<3;++h){g=j+h
if(!(g<t))return A.a(a3,g)
g=a3[g]*3+1
if(!(g>=0&&g<k))return A.a(a5,g)
if(a5[g]>o)i=!1}B.c.A((i?n:m).c,l)}f=A.m_(b0,a1)
e=A.m_(b0,a7)
B.c.A(b2,"split the single material geometrically at the "+B.b.bn(p,1)+' mm line: "upper" gets '+a6.length+" triangles ("+A.m9(f-e,f)+' of the surface), "sole" gets '+a7.length+" ("+A.m9(e,f)+") \u2014 an approximation for a one-material scan, and the cut line stays a reviewer question (checklist \xa76)")
a3=u.eK
a3=A.q(new A.bs(A.j([m,n],u.cE),u.fJ.a(new A.jc()),a3),a3.v("e.E"))
return a3}for(t=b0.d,k=b0.e,l=0;l<(t.length/3|0);++l){if(!(l<k.length))return A.a(k,l)
q.$2(k[l],l)}t=r.$ti.v("dR<2>")
d=A.q(new A.dR(r,t),t.v("e.E"))
c=A.j([],a3)
for(a8=0;a8<a4.length;++a8){a3=a9.b_(a0,a8).k(0,a2)
a3=a3==null?a1:J.ac(a3)
if(a3==null)a3=""
if(!(a8<a4.length))return A.a(a4,a8)
if(a3!==a4[a8]){a3=A.z(a9.b_(a0,a8).k(0,a2))
if(!(a8<a4.length))return A.a(a4,a8)
B.c.A(c,a3+" \u2192 "+a4[a8])}}if(c.length!==0)B.c.A(b2,"renamed material(s): "+B.c.c9(c,", "))
b=A.lr(a5)
a3=u.Y
a8=0
for(;;){if(!(a8<J.ao(a7.b(a6.k(0,a0))?a7.a(a6.k(0,a0)):B.J)))break
a5=a3.a(a9.b_(a0,a8).k(0,"extensions"))
a5=a5==null?a1:a5.gbw()
a5=J.bu(a5==null?B.im:a5)
while(a5.F()){a=a5.gM()
t=J.bt(a)
if(B.c5.aR(0,t.D(a)))b.A(0,t.D(a))}++a8}if(b.a!==0)B.c.A(b2,"removed extension(s) the renderer has no proven support for: "+b.c9(0,", "))
a3=d.length
if(a3===1)B.c.A(b2,"note: the model has "+a3+' material named "'+B.c.gdI(d).a+'" \u2014 the contract requires both "upper" and "sole"; pass --sole-band-mm to cut a sole band, or split the parts in the modelling tool (guide \xa7C6)')
return d},
pR(d3,d4,d5,d6,d7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9="name",c0="materials",c1="extensions",c2="textures",c3="samplers",c4="nodes",c5=new A.iI($.jJ()),c6=u.c7,c7=A.j([],c6),c8=A.j([],c6),c9=new A.jj(c5,c7),d0=new A.jo(),d1=new A.jp(),d2=A.j([],c6)
for(t=d6.length,s=u.N,r=u.z,q=u.p,p=u.n,o=d3.d,n=u.t,m=0;m<d6.length;d6.length===t||(0,A.a_)(d6),++m){l=d6[m]
k=A.D(q,q)
j=A.j([],p)
i=A.j([],p)
h=A.j([],p)
g=A.j([],n)
for(f=l.c,e=f.length,d=0;d<f.length;f.length===e||(0,A.a_)(f),++d)for(c=f[d]*3,b=0;b<3;++b){a=c+b
if(!(a<o.length))return A.a(o,a)
a0=o[a]
B.c.A(g,k.fa(a0,new A.jk(j,d3,a0,i,h)))}a1=A.j([1/0,1/0,1/0],p)
a2=A.j([-1/0,-1/0,-1/0],p)
for(a3=0;a3<j.length;a3+=3)for(a4=0;a4<3;++a4){if(!(a4<a1.length))return A.a(a1,a4)
f=a1[a4]
e=a3+a4
if(!(e<j.length))return A.a(j,e)
B.c.i(a1,a4,Math.min(f,j[e]))
if(!(a4<a2.length))return A.a(a2,a4)
f=a2[a4]
if(!(e<j.length))return A.a(j,e)
B.c.i(a2,a4,Math.max(f,j[e]))}B.c.A(c8,A.aD(["bufferView",c9.$2$stride(d0.$1(j),0),"componentType",5126,"count",j.length/3|0,"type","VEC3","min",a1,"max",a2],s,r))
f=c8.length
if(i.length!==0){B.c.A(c8,A.aD(["bufferView",c9.$2$stride(d0.$1(i),0),"componentType",5126,"count",i.length/3|0,"type","VEC3"],s,r))
a5=c8.length-1}else a5=null
if(h.length!==0){B.c.A(c8,A.aD(["bufferView",c9.$2$stride(d0.$1(h),0),"componentType",5126,"count",h.length/2|0,"type","VEC2"],s,r))
a6=c8.length-1}else a6=null
a7=(j.length/3|0)<=65535
a8=c9.$2$stride(d1.$2(g,a7?2:4),0)
e=a7?5123:5125
B.c.A(c8,A.aD(["bufferView",a8,"componentType",e,"count",g.length,"type","SCALAR"],s,r))
e=c8.length
B.c.A(d7,'part "'+l.a+'": '+(g.length/3|0)+" triangles, "+(j.length/3|0)+" vertices")
c=A.D(s,q)
c.i(0,"POSITION",f-1)
if(a5!=null)c.i(0,"NORMAL",a5)
if(a6!=null)c.i(0,"TEXCOORD_0",a6)
B.c.A(d2,A.aD(["attributes",c,"indices",e-1,"mode",4,"material",B.c.jf(d6,l)],s,r))}a9=A.j([],c6)
for(t=d5.length,m=0;m<d5.length;d5.length===t||(0,A.a_)(d5),++m){b0=d5[m]
b1=c9.$2$stride(b0.c,0)
p=A.D(s,r)
o=b0.a
if(o!=null&&o.length!==0)p.i(0,b9,o)
p.i(0,"mimeType",b0.b)
p.i(0,"bufferView",b1)
B.c.A(a9,p)}b2=A.j([],c6)
b3=A.lr(s)
for(c6=d6.length,t=u.f,m=0;m<d6.length;d6.length===c6||(0,A.a_)(d6),++m){l=d6[m]
p=l.b
b4=p>=0?A.b3(d4.b_(c0,p),s,r):A.aD(["pbrMetallicRoughness",A.D(s,r)],s,r)
b4.i(0,b9,l.a)
b5=b4.k(0,c1)
if(t.b(b5)){b6=A.D(s,r)
b5.aT(0,new A.jl(b6,b3))
if(b6.a===0)b4.bT(0,c1)
else b4.i(0,c1,b6)}b4.bT(0,"extras")
B.c.A(b2,b4)}c6=u.c
t=J.ba(d4.bc(c2),new A.jm(),c6)
b7=A.q(t,t.$ti.v("a1.E"))
c6=J.ba(d4.bc(c3),new A.jn(),c6)
b8=A.q(c6,c6.$ti.v("a1.E"))
while(B.a.a1(c5.gt(0),4)!==0)c5.eM(0)
c6=A.D(s,r)
c6.i(0,"asset",A.aD(["version","2.0","generator","solevision glb normalizer"],s,s))
c6.i(0,"scene",0)
c6.i(0,"scenes",A.j([A.aD(["nodes",A.j([0],n)],s,u.L)],u.b8))
if(J.kR(d4.bc(c4))){t=d4.b_(c4,0).k(0,b9)
t=t==null?null:J.ac(t)
if(t==null)t="shoe"}else t="shoe"
r=u.K
p=u.ez
c6.i(0,c4,A.j([A.aD(["mesh",0,"name",t],s,r)],p))
c6.i(0,"meshes",A.j([A.aD(["name","shoe","primitives",d2],s,r)],p))
c6.i(0,"accessors",c8)
c6.i(0,"bufferViews",c7)
c6.i(0,"buffers",A.j([A.aD(["byteLength",c5.gt(0)],s,q)],u.a4))
c6.i(0,c0,b2)
if(b7.length!==0)c6.i(0,c2,b7)
if(b8.length!==0)c6.i(0,c3,b8)
if(a9.length!==0)c6.i(0,"images",a9)
if(b3.a!==0){t=A.q(b3,b3.$ti.c)
B.c.fz(t)
c6.i(0,"extensionsUsed",t)}return A.p1(c6,c5.jx())},
p1(a,b){var t,s=B.cA.cm(B.K.d4(a,null)),r=s.length,q=B.a.a1(4-B.a.a1(r,4),4),p=b.length,o=B.a.a1(4-B.a.a1(p,4),4),n=20+r,m=n+q,l=m+8,k=l+p,j=k+o,i=new DataView(new ArrayBuffer(j))
i.setUint32(0,1179937895,!0)
i.setUint32(4,2,!0)
i.setUint32(8,j,!0)
i.setUint32(12,r+q,!0)
i.setUint32(16,1313821514,!0)
B.e.d9(A.io(J.ab(B.W.gB(i)),20,n),0,s)
for(t=0;t<q;++t)i.setUint8(n+t,32)
i.setUint32(m,p+o,!0)
i.setUint32(m+4,5130562,!0)
B.e.d9(A.io(J.ab(B.W.gB(i)),l,k),0,b)
return J.ab(B.W.gB(i))},
m7(a,b,c){var t,s=a.d3(),r=a.d.length,q=a.a.length,p=A.j([],u.n)
for(t=0;t<6;++t)p.push(s[t]*1000)
return A.aD(["bytes",c,"triangles",r/3|0,"vertices",q/3|0,"materials",b,"boundsMm",p,"lengthMm",(s[5]-s[2])*1000,"widthMm",(s[3]-s[0])*1000,"heightMm",(s[4]-s[1])*1000],u.N,u.z)},
m9(a,b){return b<=0?"n/a":B.b.bn(100*a/b,1)+"%"},
m_(a5,a6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=a6==null,a4=a3?null:a6.length
if(a4==null)a4=a5.d.length/3|0
for(t=a5.d,s=a5.a,r=0,q=0;q<a4;++q){if(a3)p=null
else{if(!(q<a6.length))return A.a(a6,q)
o=a6[q]
p=o}o=(p==null?q:p)*3
n=t.length
if(!(o<n))return A.a(t,o)
m=t[o]
l=o+1
if(!(l<n))return A.a(t,l)
k=t[l]
o+=2
if(!(o<n))return A.a(t,o)
j=t[o]
o=k*3
n=s.length
if(!(o>=0&&o<n))return A.a(s,o)
l=s[o]
i=m*3
if(!(i>=0&&i<n))return A.a(s,i)
h=s[i]
g=l-h
l=o+1
if(!(l<n))return A.a(s,l)
l=s[l]
f=i+1
if(!(f<n))return A.a(s,f)
f=s[f]
e=l-f
o+=2
if(!(o<n))return A.a(s,o)
o=s[o]
i+=2
if(!(i<n))return A.a(s,i)
i=s[i]
d=o-i
o=j*3
if(!(o>=0&&o<n))return A.a(s,o)
c=s[o]-h
h=o+1
if(!(h<n))return A.a(s,h)
b=s[h]-f
o+=2
if(!(o<n))return A.a(s,o)
a=s[o]-i
a0=e*a-d*b
a1=d*c-g*a
a2=g*b-e*c
r+=Math.sqrt(a0*a0+a1*a1+a2*a2)/2}return r},
m2(a){var t=J.ba(a.bc("materials"),new A.j2(),u.N)
t=A.q(t,t.$ti.v("a1.E"))
return t},
ji(a){if(a<1024)return""+a+" B"
if(a<1048576)return B.b.bn(a/1024,1)+" KB"
return B.b.bn(a/1048576,2)+" MiB"},
db:function db(a,b){this.a=a
this.b=b},
hG:function hG(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.d=c
_.e=d
_.f=e
_.r=f},
hF:function hF(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
a7:function a7(a){this.a=a},
iM:function iM(a,b){this.a=a
this.b=b},
jd:function jd(){},
je:function je(){},
iL:function iL(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
j9:function j9(a){this.a=a},
j4:function j4(){},
j5:function j5(){},
j6:function j6(){},
j7:function j7(){},
jf:function jf(){},
jh:function jh(a,b){this.a=a
this.b=b},
jg:function jg(a){this.a=a},
ha:function ha(a,b,c){this.a=a
this.b=b
this.c=c},
aF:function aF(a,b,c){this.a=a
this.b=b
this.c=c},
ja:function ja(a,b,c){this.a=a
this.b=b
this.c=c},
jb:function jb(a,b){this.a=a
this.b=b},
jc:function jc(){},
jj:function jj(a,b){this.a=a
this.b=b},
jo:function jo(){},
jp:function jp(){},
jk:function jk(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
jl:function jl(a,b){this.a=a
this.b=b},
jm:function jm(){},
jn:function jn(){},
j2:function j2(){},
fa(a){var t=new A.hH()
t.fI(a)
return t},
hH:function hH(){this.a=$
this.b=0
this.c=2147483647},
iG:function iG(){},
j_:function j_(){},
hP:function hP(a,b){var _=this
_.a=a
_.b=null
_.c=b
_.e=_.d=0},
iF:function iF(){},
eS:function eS(a,b){this.a=a
this.b=b},
jW(a,b,c,d){var t,s,r=new A.fi(b)
if(d==null)d=0
if(c==null)c=a.length-d
t=a.length
if(d+c>t)c=t-d
s=u.D.b(a)?a:new Uint8Array(A.w(a))
t=J.V(B.e.gB(s),s.byteOffset+d,c)
r.b=t
r.d=t.length
return r},
fi:function fi(a){var _=this
_.b=null
_.c=0
_.d=$
_.a=a},
fj:function fj(){},
nC(a,b){var t=b==null?32768:b
return new A.e4(new Uint8Array(t),a)},
e4:function e4(a,b){this.b=0
this.c=a
this.a=b},
fG:function fG(){},
hu:function hu(a,b){this.a=a
this.b=b},
L:function L(a){this.a=-1
this.b=a},
cz:function cz(a){this.a=a},
cA:function cA(a){this.a=a},
cB:function cB(a){this.a=a},
cC:function cC(a){this.a=a},
cD:function cD(a){this.a=a},
cE:function cE(a){this.a=a},
cF:function cF(a,b){this.a=a
this.b=b},
cG:function cG(a){this.a=a},
cH:function cH(a,b){this.a=a
this.b=b},
cI:function cI(a){this.a=a},
cJ:function cJ(a,b){this.a=a
this.b=b},
l_(a,b,c,d){var t=new A.bT(new Uint8Array(4))
t.fD(a,b,c,d)
return t},
aS:function aS(a){this.a=a},
eV:function eV(a){this.a=a},
bT:function bT(a){this.a=a},
dl:function dl(a){this.a=a},
eY:function eY(a){this.a=a},
hk(a,b,c){var t
if(b===c)return a
switch(b.a){case 0:if(a===0)t=0
else{t=B.bT.k(0,c)
t.toString}return t
case 1:switch(c.a){case 0:return a===0?0:1
case 1:return a
case 2:return a*5
case 3:return a*75
case 4:return a*21845
case 5:return a*1431655765
case 6:return a*42
case 7:return a*10922
case 8:return a*715827882
case 9:case 10:case 11:return a/3}break
case 2:switch(c.a){case 0:return a===0?0:1
case 1:return B.a.j(A.u(a),1)
case 2:return a
case 3:return a*17
case 4:return a*4369
case 5:return a*286331153
case 6:return a*8
case 7:return a*2184
case 8:return a*143165576
case 9:case 10:case 11:return a/3}break
case 3:switch(c.a){case 0:return a===0?0:1
case 1:return B.a.j(A.u(a),6)
case 2:return B.a.j(A.u(a),4)
case 3:return a
case 4:return a*257
case 5:return a*16843009
case 6:return B.a.j(A.u(a),1)
case 7:return a*128
case 8:return a*8421504
case 9:case 10:case 11:return a/255}break
case 4:switch(c.a){case 0:return a===0?0:1
case 1:return B.a.j(A.u(a),14)
case 2:return B.a.j(A.u(a),12)
case 3:return B.a.j(A.u(a),8)
case 4:return a
case 5:return A.u(a)<<8>>>0
case 6:return B.a.j(A.u(a),9)
case 7:return B.a.j(A.u(a),1)
case 8:return a*524296
case 9:case 10:case 11:return a/65535}break
case 5:switch(c.a){case 0:return a===0?0:1
case 1:return B.a.j(A.u(a),30)
case 2:return B.a.j(A.u(a),28)
case 3:return B.a.j(A.u(a),24)
case 4:return B.a.j(A.u(a),16)
case 5:return a
case 6:return B.a.j(A.u(a),25)
case 7:return B.a.j(A.u(a),17)
case 8:return B.a.j(A.u(a),1)
case 9:case 10:case 11:return a/4294967295}break
case 6:switch(c.a){case 0:return a===0?0:1
case 1:return a<=0?0:B.a.j(A.u(a),5)
case 2:return a<=0?0:B.a.j(A.u(a),3)
case 3:return a<=0?0:A.u(a)<<1>>>0
case 4:return a<=0?0:A.u(a)*516
case 5:return a<=0?0:A.u(a)*33818640
case 6:return a
case 7:return a*258
case 8:return a*16909320
case 9:case 10:case 11:return a/127}break
case 7:switch(c.a){case 0:return a===0?0:1
case 1:return a<=0?0:B.a.j(A.u(a),15)
case 2:return a<=0?0:B.a.j(A.u(a),11)
case 3:return a<=0?0:B.a.j(A.u(a),7)
case 4:return a<=0?0:A.u(a)<<1>>>0
case 5:return a<=0?0:A.u(a)*131076
case 6:return B.a.j(A.u(a),8)
case 7:return a
case 8:return A.u(a)*65538
case 9:case 10:case 11:return a/32767}break
case 8:switch(c.a){case 0:return a===0?0:1
case 1:return a<=0?0:B.a.j(A.u(a),29)
case 2:return a<=0?0:B.a.j(A.u(a),27)
case 3:return a<=0?0:B.a.j(A.u(a),23)
case 4:return a<=0?0:B.a.j(A.u(a),16)
case 5:return a<=0?0:A.u(a)<<1>>>0
case 6:return B.a.j(A.u(a),24)
case 7:return B.a.j(A.u(a),16)
case 8:return a
case 9:case 10:case 11:return a/2147483647}break
case 9:case 10:case 11:switch(c.a){case 0:return a===0?0:1
case 1:return B.b.h(B.b.J(a,0,1)*3)
case 2:return B.b.h(B.b.J(a,0,1)*15)
case 3:return B.b.h(B.b.J(a,0,1)*255)
case 4:return B.b.h(B.b.J(a,0,1)*65535)
case 5:return B.b.h(B.b.J(a,0,1)*4294967295)
case 6:return B.b.h(a<0?B.b.J(a,-1,1)*128:B.b.J(a,-1,1)*127)
case 7:return B.b.h(a<0?B.b.J(a,-1,1)*32768:B.b.J(a,-1,1)*32767)
case 8:return B.b.h(a<0?B.b.J(a,-1,1)*2147483648:B.b.J(a,-1,1)*2147483647)
case 9:case 10:case 11:return a}break}},
ap:function ap(a,b){this.a=a
this.b=b},
eQ:function eQ(a,b){this.a=a
this.b=b},
ds(a){var t,s=new A.bw(A.D(u.N,u.P))
s.fJ(a)
t=a.b
if(t!=null)s.b=new Uint8Array(A.w(t))
return s},
jP(a){var t=new A.bw(A.D(u.N,u.P))
t.bS(a)
return t},
bw:function bw(a){this.b=null
this.a=a},
hc:function hc(a,b){this.a=a
this.b=b},
i(a,b,c){return new A.f1(a,b)},
f1:function f1(a,b){this.a=a
this.b=b},
aK:function aK(a){this.a=a},
hJ:function hJ(a){this.a=a},
l7(a){var t=new A.aC(A.D(u.p,u.r),new A.aK(A.D(u.N,u.P)))
t.iZ(a)
return t},
aC:function aC(a,b){this.a=a
this.b=b},
hK:function hK(a){this.a=a},
hL:function hL(a){this.a=a},
le(a,b){var t=new A.c3(new Uint16Array(b))
t.fO(a,b)
return t},
jU(a){var t=new Uint32Array(1)
t[0]=a
return new A.aU(t)},
l9(a,b){var t=new A.aU(new Uint32Array(b))
t.fL(a,b)
return t},
la(a,b){var t,s=J.c4(b,u.k)
for(t=0;t<b;++t)s[t]=new A.d9(a.l(),a.l())
return new A.c_(s)},
ld(a,b){var t=new A.c2(new Int16Array(b))
t.fN(a,b)
return t},
lb(a,b){var t=new A.c0(new Int32Array(b))
t.fM(a,b)
return t},
lc(a,b){var t,s,r,q,p=J.c4(b,u.k)
for(t=0;t<b;++t){s=a.l()
r=$.K()
r.$flags&2&&A.b(r)
r[0]=s
s=$.a4()
if(0>=s.length)return A.a(s,0)
q=s[0]
r[0]=a.l()
p[t]=new A.d9(q,s[0])}return new A.c1(p)},
lf(a,b){var t=new A.cP(new Float32Array(b))
t.fP(a,b)
return t},
l8(a,b){var t=new A.cN(new Float64Array(b))
t.fK(a,b)
return t},
ae:function ae(a,b){this.a=a
this.b=b},
a0:function a0(){},
bg:function bg(a){this.a=a},
bZ:function bZ(a){this.a=a},
c3:function c3(a){this.a=a},
aU:function aU(a){this.a=a},
c_:function c_(a){this.a=a},
by:function by(a){this.a=a},
c2:function c2(a){this.a=a},
c0:function c0(a){this.a=a},
c1:function c1(a){this.a=a},
cP:function cP(a){this.a=a},
cN:function cN(a){this.a=a},
cQ:function cQ(a){this.a=a},
cO:function cO(a){this.a=a},
kT(a){var t,s,r=new A.ht()
if(!A.kU(a))A.aA(A.n("Not a bitmap file."))
a.d+=2
t=a.l()
s=$.K()
s.$flags&2&&A.b(s)
s[0]=t
t=$.a4()
if(0>=t.length)return A.a(t,0)
a.d+=4
s[0]=a.l()
r.b=t[0]
return r},
kU(a){if(a.c-a.d<2)return!1
return A.o(a,null,0).m()===19778},
mS(a,b){var t,s,r,q,p=b==null?A.kT(a):b,o=a.d,n=a.l(),m=a.l(),l=$.K()
l.$flags&2&&A.b(l)
l[0]=m
m=$.a4()
if(0>=m.length)return A.a(m,0)
t=m[0]
l[0]=a.l()
m=m[0]
s=a.m()
r=a.m()
q=a.l()
if(q>=14)A.aA(A.n("Unsupported BMP compression type: "+q))
if(!(q<14))return A.a(B.af,q)
q=B.af[q]
a.l()
l[0]=a.l()
l[0]=a.l()
l=a.l()
a.l()
o=new A.bc(p,t,m,n,s,r,q,l,o)
o.dU(a,b)
return o},
ad:function ad(a,b){this.a=a
this.b=b},
ht:function ht(){this.b=$},
bc:function bc(a,b,c,d,e,f,g,h,i){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.z=h
_.ay=_.ax=_.at=_.as=$
_.ch=null
_.fx=_.fr=_.dy=_.dx=_.db=_.cy=_.cx=_.CW=$
_.fy=i},
eR:function eR(a){this.a=$
this.b=null
this.c=a},
hs:function hs(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
hw:function hw(a){this.a=$
this.b=null
this.c=a},
J:function J(){},
hv:function hv(){},
hx:function hx(){},
f2:function f2(){},
dI:function dI(a,b,c,d){var _=this
_.r=a
_.w=b
_.x=c
_.b=_.a=0
_.c=d},
cL:function cL(a,b){this.a=a
this.b=b},
bV:function bV(a,b){this.a=a
this.b=b},
f3:function f3(){var _=this
_.w=_.r=_.f=_.d=_.c=_.b=_.a=$},
l0(a,b,c,d){var t,s
switch(a.a){case 1:return new A.fp(c,b)
case 2:return new A.dJ(c,d==null?1:d,b)
case 3:return new A.dJ(c,d==null?16:d,b)
case 4:t=d==null?32:d
s=new A.fn(c,t,b)
s.fS(b,c,t)
return s
case 5:return new A.fo(c,d==null?16:d,b)
case 6:return new A.dI(c,d==null?32:d,!1,b)
case 7:return new A.dI(c,d==null?32:d,!0,b)
default:throw A.f(A.n("Invalid compression type: "+a.D(0)))}},
aT:function aT(a,b){this.a=a
this.b=b},
be:function be(){},
fl:function fl(){},
n4(a,b,c,d){var t,s,r,q,p,o,n,m
if(b===0){if(d!==0)throw A.f(A.n("Incomplete huffman data"))
return}t=a.d
s=a.l()
r=a.l()
a.d+=4
q=a.l()
p=!0
if(s<65537)p=r>=65537
if(p)throw A.f(A.n("Invalid huffman table size"))
a.d+=4
o=A.P(65537,0,!1,u.p)
n=J.ag(16384,u.gV)
for(m=0;m<16384;++m)n[m]=new A.f4()
A.n5(a,b-20,s,r,o)
if(q>8*(b-(a.d-t)))throw A.f(A.n("Error in header for Huffman-encoded data (invalid number of bits)."))
A.n1(o,s,r,n)
A.n3(o,n,a,q,r,d,c)},
n3(a,b,c,d,e,f,g){var t,s,r,q,p,o,n,m,l,k="Error in Huffman-encoded data (invalid code).",j=A.j([0,0],u.t),i=c.d+B.a.Y(d+7,8)
for(t=b.length,s=0;c.d<i;){A.jQ(j,c)
while(r=j[1],r>=14){q=B.a.bs(j[0],r-14)&16383
if(!(q<t))return A.a(b,q)
p=b[q]
q=p.a
if(q!==0){B.c.i(j,1,r-q)
s=A.jR(p.b,e,j,c,g,s,f)}else{if(p.c==null)throw A.f(A.n(k))
for(o=0;o<p.b;++o){r=p.c
if(!(o<r.length))return A.a(r,o)
r=r[o]
if(!(r<65537))return A.a(a,r)
n=a[r]&63
for(;;){r=j[1]
if(!(r<n&&c.d<i))break
A.jQ(j,c)}if(r>=n){q=p.c
if(!(o<q.length))return A.a(q,o)
q=q[o]
if(!(q<65537))return A.a(a,q)
r-=n
if(a[q]>>>6===(B.a.bs(j[0],r)&B.a.O(1,n)-1)>>>0){B.c.i(j,1,r)
r=p.c
if(!(o<r.length))return A.a(r,o)
m=A.jR(r[o],e,j,c,g,s,f)
s=m
break}}}if(o===p.b)throw A.f(A.n(k))}}}l=8-d&7
B.c.i(j,0,B.a.j(j[0],l))
B.c.i(j,1,j[1]-l)
while(r=j[1],r>0){q=B.a.W(j[0],14-r)&16383
if(!(q<t))return A.a(b,q)
p=b[q]
q=p.a
if(q!==0){B.c.i(j,1,r-q)
s=A.jR(p.b,e,j,c,g,s,f)}else throw A.f(A.n(k))}if(s!==f)throw A.f(A.n("Error in Huffman-encoded data (decoded data are shorter than expected)."))},
jR(a,b,c,d,e,f,g){var t,s,r,q,p,o,n="Error in Huffman-encoded data (decoded data are longer than expected)."
if(a===b){if(c[1]<8)A.jQ(c,d)
B.c.i(c,1,c[1]-8)
t=B.a.bs(c[0],c[1])&255
if(f+t>g)throw A.f(A.n(n))
s=f-1
r=e.length
if(!(s>=0&&s<r))return A.a(e,s)
q=e[s]
for(s=e.$flags|0;p=t-1,t>0;t=p,f=o){o=f+1
s&2&&A.b(e)
if(!(f<r))return A.a(e,f)
e[f]=q}}else{if(f<g){e.toString
o=f+1
e.$flags&2&&A.b(e)
if(!(f<e.length))return A.a(e,f)
e[f]=a}else throw A.f(A.n(n))
f=o}return f},
n1(a,b,c,d){var t,s,r,q,p,o,n,m,l,k,j="Error in Huffman-encoded data (invalid code table entry)."
for(t=d.length,s=u.t,r=u.p;b<=c;++b){if(!(b<65537))return A.a(a,b)
q=a[b]
p=q>>>6
o=q&63
if(B.a.a_(p,o)!==0)throw A.f(A.n(j))
if(o>14){q=B.a.a0(p,o-14)
if(!(q<t))return A.a(d,q)
n=d[q]
if(n.a!==0)throw A.f(A.n(j))
q=++n.b
m=n.c
if(m!=null){n.sf9(A.P(q,0,!1,r))
for(l=0;l<n.b-1;++l){q=n.c
q.toString
if(!(l<m.length))return A.a(m,l)
B.c.i(q,l,m[l])}}else n.sf9(A.j([0],s))
q=n.c
q.toString
B.c.i(q,n.b-1,b)}else if(o!==0){q=14-o
k=B.a.W(p,q)
if(!(k<t))return A.a(d,k)
for(l=B.a.W(1,q);l>0;--l,++k){if(!(k<t))return A.a(d,k)
n=d[k]
if(n.a!==0||n.c!=null)throw A.f(A.n(j))
n.a=o
n.b=b}}}},
n5(a,b,c,d,e){var t,s,r,q,p,o="Error in Huffman-encoded data (unexpected end of code table data).",n="Error in Huffman-encoded data (code table is longer than expected).",m=a.d,l=A.j([0,0],u.t)
for(t=d+1;c<=d;++c){if(a.d-m>b)throw A.f(A.n(o))
s=A.l1(6,l,a)
B.c.i(e,c,s)
if(s===63){if(a.d-m>b)throw A.f(A.n(o))
r=A.l1(8,l,a)+6
if(c+r>t)throw A.f(A.n(n))
for(;q=r-1,r!==0;r=q,c=p){p=c+1
B.c.i(e,c,0)}--c}else if(s>=59){r=s-59+2
if(c+r>t)throw A.f(A.n(n))
for(;q=r-1,r!==0;r=q,c=p){p=c+1
B.c.i(e,c,0)}--c}}A.n2(e)},
n2(a){var t,s,r,q,p,o=A.P(59,0,!1,u.p)
for(t=0;t<65537;++t){s=a[t]
if(!(s<59))return A.a(o,s)
B.c.i(o,s,o[s]+1)}for(r=0,t=58;t>0;--t,r=q){q=r+o[t]>>>1
B.c.i(o,t,r)}for(t=0;t<65537;++t){p=a[t]
if(p>0){if(!(p<59))return A.a(o,p)
s=o[p]
B.c.i(o,p,s+1)
B.c.i(a,t,(p|s<<6)>>>0)}}},
jQ(a,b){B.c.i(a,0,((a[0]<<8|b.G())&-1)>>>0)
B.c.i(a,1,(a[1]+8&-1)>>>0)},
l1(a,b,c){var t
while(t=b[1],t<a){B.c.i(b,0,((b[0]<<8|J.c(c.a,c.d++))&-1)>>>0)
B.c.i(b,1,(b[1]+8&-1)>>>0)}B.c.i(b,1,t-a)
return(B.a.bs(b[0],b[1])&B.a.O(1,a)-1)>>>0},
f4:function f4(){this.b=this.a=0
this.c=null},
n6(a){var t=A.v(a,!1,null,0)
if(t.l()!==20000630)return!1
if(t.G()!==2)return!1
if((t.bf()&4294967289)>>>0!==0)return!1
return!0},
f5:function f5(a){var _=this
_.b=_.a=0
_.c=a
_.d=null
_.e=$},
lh(a,b,c){var t=new A.fm(a,A.j([],u.g9),A.D(u.N,u.aX),B.aT,b)
t.fG(a,b,c)
return t},
dt:function dt(){},
hz:function hz(a,b){this.a=a
this.b=b},
fm:function fm(a,b,c,d,e){var _=this
_.a=a
_.b=null
_.c=b
_.d=0
_.e=c
_.r=$
_.x=_.w=0
_.at=$
_.ax=d
_.ay=null
_.ch=$
_.CW=null
_.cx=0
_.cy=null
_.db=e
_.k1=_.id=_.go=_.fy=_.fx=_.fr=_.dy=_.dx=null
_.k2=$
_.k3=null},
fn:function fn(a,b,c){var _=this
_.r=null
_.w=a
_.x=b
_.y=$
_.z=null
_.b=_.a=0
_.c=c},
eH:function eH(){var _=this
_.f=_.e=_.d=_.c=_.b=_.a=$},
fo:function fo(a,b,c){var _=this
_.w=a
_.x=b
_.y=null
_.b=_.a=0
_.c=c},
fp:function fp(a,b){var _=this
_.r=null
_.w=a
_.b=_.a=0
_.c=b},
dJ:function dJ(a,b,c){var _=this
_.w=a
_.x=b
_.y=null
_.b=_.a=0
_.c=c},
hy:function hy(){this.a=null},
l4(a){var t=new Uint8Array(a*3)
return new A.dw(A.nd(a),a,null,new A.aW(t,a,3))},
nc(a){return new A.dw(a.a,a.b,a.c,A.lx(a.d))},
nd(a){var t
for(t=1;t<=8;++t)if(B.a.O(1,t)>=a)return t
return 0},
dw:function dw(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dx:function dx(){},
fq:function fq(){var _=this
_.e=_.d=_.c=_.b=_.a=$
_.f=null
_.r=80
_.w=0
_.x=-1
_.y=$},
dy:function dy(a){var _=this
_.b=_.a=0
_.e=_.c=null
_.r=a},
hE:function hE(){var _=this
_.a=null
_.e=_.d=_.c=_.b=0
_.f=null
_.r=0
_.w=null
_.y=_.x=$
_.z=null
_.Q=0
_.as=null
_.ay=_.ax=_.at=0
_.ch=null
_.dy=_.dx=_.db=_.cy=_.cx=_.CW=0},
l6(a){var t,s,r,q
if(a.m()!==0)return null
t=a.m()
if(t>=3)return null
if(B.dl[t]===B.aW)return null
s=a.m()
r=J.c4(s,u.gx)
for(q=0;q<s;++q){J.c(a.a,a.d++)
J.c(a.a,a.d++)
J.c(a.a,a.d++);++a.d
a.m()
a.m()
r[q]=new A.ff(a.l(),a.l())}return new A.fe(s,r)},
cM:function cM(a,b){this.a=a
this.b=b},
fe:function fe(a,b){this.d=a
this.e=b},
ff:function ff(a,b){this.d=a
this.e=b},
fd:function fd(a,b,c,d,e,f,g,h,i){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.z=h
_.ay=_.ax=_.at=_.as=$
_.ch=null
_.fx=_.fr=_.dy=_.dx=_.db=_.cy=_.cx=_.CW=$
_.fy=i},
hI:function hI(){this.b=this.a=null},
eW:function eW(a,b,c){this.e=a
this.f=b
this.r=c},
bx:function bx(){},
bY:function bY(a){this.a=a},
dC:function dC(a){this.a=a},
qi(b2,b3,b4,b5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1
if($.kv==null){t=new Uint8Array(768)
for(s=0;s<256;++s){r=256+s
if(!(r<768))return A.a(t,r)
t[r]=s}for(s=256;s<512;++s){r=256+s
if(!(r<768))return A.a(t,r)
t[r]=255}$.kv=t}for(r=b5.$flags|0,s=0;s<64;++s){q=b3[s]
p=b2[s]
r&2&&A.b(b5)
if(!(s<64))return A.a(b5,s)
b5[s]=q*p}for(o=0,s=0;s<8;++s,o+=8){q=1+o
if(!(q<64))return A.a(b5,q)
p=b5[q]
n=!1
if(p===0){m=2+o
if(!(m<64))return A.a(b5,m)
if(b5[m]===0){m=3+o
if(!(m<64))return A.a(b5,m)
if(b5[m]===0){m=4+o
if(!(m<64))return A.a(b5,m)
if(b5[m]===0){m=5+o
if(!(m<64))return A.a(b5,m)
if(b5[m]===0){m=6+o
if(!(m<64))return A.a(b5,m)
if(b5[m]===0){n=7+o
if(!(n<64))return A.a(b5,n)
n=b5[n]===0}}}}}}if(n){if(!(o<64))return A.a(b5,o)
q=B.a.j(5793*b5[o]+512,10)
l=(q&2147483647)-((q&2147483648)>>>0)
r&2&&A.b(b5)
if(!(o<64))return A.a(b5,o)
b5[o]=l
q=o+1
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+2
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+3
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+4
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+5
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+6
if(!(q<64))return A.a(b5,q)
b5[q]=l
q=o+7
if(!(q<64))return A.a(b5,q)
b5[q]=l
continue}if(!(o<64))return A.a(b5,o)
n=B.a.j(5793*b5[o]+128,8)
k=(n&2147483647)-((n&2147483648)>>>0)
n=4+o
if(!(n<64))return A.a(b5,n)
m=B.a.j(5793*b5[n]+128,8)
j=(m&2147483647)-((m&2147483648)>>>0)
m=2+o
if(!(m<64))return A.a(b5,m)
i=b5[m]
h=6+o
if(!(h<64))return A.a(b5,h)
g=b5[h]
f=7+o
if(!(f<64))return A.a(b5,f)
e=b5[f]
d=B.a.j(2896*(p-e)+128,8)
c=(d&2147483647)-((d&2147483648)>>>0)
e=B.a.j(2896*(p+e)+128,8)
b=(e&2147483647)-((e&2147483648)>>>0)
e=3+o
if(!(e<64))return A.a(b5,e)
p=b5[e]<<4
a=(p&2147483647)-((p&2147483648)>>>0)
p=5+o
if(!(p<64))return A.a(b5,p)
d=b5[p]<<4
a0=(d&2147483647)-((d&2147483648)>>>0)
d=B.a.j(k-j+1,1)
l=(d&2147483647)-((d&2147483648)>>>0)
d=B.a.j(k+j+1,1)
k=(d&2147483647)-((d&2147483648)>>>0)
d=B.a.j(i*3784+g*1567+128,8)
d=(d&2147483647)-((d&2147483648)>>>0)
a1=B.a.j(i*1567-g*3784+128,8)
i=(a1&2147483647)-((a1&2147483648)>>>0)
a1=B.a.j(c-a0+1,1)
a1=(a1&2147483647)-((a1&2147483648)>>>0)
a2=B.a.j(c+a0+1,1)
c=(a2&2147483647)-((a2&2147483648)>>>0)
a2=B.a.j(b+a+1,1)
a2=(a2&2147483647)-((a2&2147483648)>>>0)
a3=B.a.j(b-a+1,1)
a=(a3&2147483647)-((a3&2147483648)>>>0)
a3=B.a.j(k-d+1,1)
a3=(a3&2147483647)-((a3&2147483648)>>>0)
d=B.a.j(k+d+1,1)
k=(d&2147483647)-((d&2147483648)>>>0)
d=B.a.j(l-i+1,1)
d=(d&2147483647)-((d&2147483648)>>>0)
a4=B.a.j(l+i+1,1)
j=(a4&2147483647)-((a4&2147483648)>>>0)
a4=B.a.j(c*2276+a2*3406+2048,12)
l=(a4&2147483647)-((a4&2147483648)>>>0)
a2=B.a.j(c*3406-a2*2276+2048,12)
c=(a2&2147483647)-((a2&2147483648)>>>0)
a2=B.a.j(a*799+a1*4017+2048,12)
a2=(a2&2147483647)-((a2&2147483648)>>>0)
a1=B.a.j(a*4017-a1*799+2048,12)
a=(a1&2147483647)-((a1&2147483648)>>>0)
r&2&&A.b(b5)
if(!(o<64))return A.a(b5,o)
b5[o]=k+l
if(!(f<64))return A.a(b5,f)
b5[f]=k-l
if(!(q<64))return A.a(b5,q)
b5[q]=j+a2
if(!(h<64))return A.a(b5,h)
b5[h]=j-a2
if(!(m<64))return A.a(b5,m)
b5[m]=d+a
if(!(p<64))return A.a(b5,p)
b5[p]=d-a
if(!(e<64))return A.a(b5,e)
b5[e]=a3+c
if(!(n<64))return A.a(b5,n)
b5[n]=a3-c}for(s=0;s<8;++s){a5=8+s
a6=16+s
a7=24+s
a8=32+s
a9=40+s
b0=48+s
b1=56+s
q=b5[a5]
if(q===0&&b5[a6]===0&&b5[a7]===0&&b5[a8]===0&&b5[a9]===0&&b5[b0]===0&&b5[b1]===0){q=B.a.j(5793*b5[s]+8192,14)
l=(q&2147483647)-((q&2147483648)>>>0)
r&2&&A.b(b5)
if(!(s<64))return A.a(b5,s)
b5[s]=l
if(!(a5<64))return A.a(b5,a5)
b5[a5]=l
if(!(a6<64))return A.a(b5,a6)
b5[a6]=l
if(!(a7<64))return A.a(b5,a7)
b5[a7]=l
if(!(a8<64))return A.a(b5,a8)
b5[a8]=l
if(!(a9<64))return A.a(b5,a9)
b5[a9]=l
if(!(b0<64))return A.a(b5,b0)
b5[b0]=l
if(!(b1<64))return A.a(b5,b1)
b5[b1]=l
continue}p=B.a.j(5793*b5[s]+2048,12)
k=(p&2147483647)-((p&2147483648)>>>0)
p=B.a.j(5793*b5[a8]+2048,12)
j=(p&2147483647)-((p&2147483648)>>>0)
i=b5[a6]
g=b5[b0]
p=b5[b1]
n=B.a.j(2896*(q-p)+2048,12)
c=(n&2147483647)-((n&2147483648)>>>0)
p=B.a.j(2896*(q+p)+2048,12)
b=(p&2147483647)-((p&2147483648)>>>0)
a=b5[a7]
a0=b5[a9]
p=B.a.j(k-j+1,1)
l=(p&2147483647)-((p&2147483648)>>>0)
p=B.a.j(k+j+1,1)
k=(p&2147483647)-((p&2147483648)>>>0)
p=B.a.j(i*3784+g*1567+2048,12)
q=(p&2147483647)-((p&2147483648)>>>0)
p=B.a.j(i*1567-g*3784+2048,12)
i=(p&2147483647)-((p&2147483648)>>>0)
p=B.a.j(c-a0+1,1)
p=(p&2147483647)-((p&2147483648)>>>0)
n=B.a.j(c+a0+1,1)
c=(n&2147483647)-((n&2147483648)>>>0)
n=B.a.j(b+a+1,1)
n=(n&2147483647)-((n&2147483648)>>>0)
m=B.a.j(b-a+1,1)
a=(m&2147483647)-((m&2147483648)>>>0)
m=B.a.j(k-q+1,1)
m=(m&2147483647)-((m&2147483648)>>>0)
q=B.a.j(k+q+1,1)
k=(q&2147483647)-((q&2147483648)>>>0)
q=B.a.j(l-i+1,1)
q=(q&2147483647)-((q&2147483648)>>>0)
h=B.a.j(l+i+1,1)
j=(h&2147483647)-((h&2147483648)>>>0)
h=B.a.j(c*2276+n*3406+2048,12)
l=(h&2147483647)-((h&2147483648)>>>0)
n=B.a.j(c*3406-n*2276+2048,12)
c=(n&2147483647)-((n&2147483648)>>>0)
n=B.a.j(a*799+p*4017+2048,12)
n=(n&2147483647)-((n&2147483648)>>>0)
p=B.a.j(a*4017-p*799+2048,12)
a=(p&2147483647)-((p&2147483648)>>>0)
r&2&&A.b(b5)
if(!(s<64))return A.a(b5,s)
b5[s]=k+l
if(!(b1<64))return A.a(b5,b1)
b5[b1]=k-l
b5[a5]=j+n
b5[b0]=j-n
b5[a6]=q+a
b5[a9]=q-a
b5[a7]=m+c
b5[a8]=m-c}for(r=$.kv,q=b4.$flags|0,s=0;s<64;++s){r.toString
p=B.a.j(b5[s]+8,4)
p=384+((p&2147483647)-((p&2147483648)>>>0))
if(!(p>=0&&p<768))return A.a(r,p)
p=r[p]
q&2&&A.b(b4)
if(!(s<64))return A.a(b4,s)
b4[s]=p}},
q4(e4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,e0,e1=null,e2="ifd0",e3=e4.w
if(e3.k(0,e2).a.ae(274)){t=e3.k(0,e2).gc3()
t.toString
s=t}else s=0
t=e4.d
r=t.e
r.toString
t=t.d
t.toString
q=s>=5&&s<=8
if(q)p=t
else p=r
if(q)o=r
else o=t
n=A.R(e1,e1,B.f,0,B.j,o,e1,0,3,e1,B.f,p,!1)
n.e=A.ds(e3)
n.gbG().k(0,e2).sc3(e1)
n.c=e4.r
m=t-1
l=r-1
switch(s){case 2:k=new A.jt(n,l)
break
case 3:k=new A.ju(n,l,m)
break
case 4:k=new A.jv(n,m)
break
case 5:k=new A.jw(n)
break
case 6:k=new A.jx(n,m)
break
case 7:k=new A.jy(n,m,l)
break
case 8:k=new A.jz(n,l)
break
default:k=n.gfs()
break}e3=e4.as
j=e3.length
switch(j){case 1:if(0>=j)return A.a(e3,0)
i=e3[0]
h=i.e
g=i.f
f=i.r
for(e3=h.length,e=0;e<t;++e){d=B.a.a_(e,f)
if(!(d<e3))return A.a(h,d)
c=h[d]
for(b=0;b<r;++b){a=B.a.a_(b,g)
if(!(a<c.length))return A.a(c,a)
a0=c[a]
k.$5(b,e,a0,a0,a0)}}break
case 3:a1=e4.c
a2=a1==null||a1.d===1
if(0>=j)return A.a(e3,0)
i=e3[0]
if(1>=j)return A.a(e3,1)
a3=e3[1]
if(2>=j)return A.a(e3,2)
a4=e3[2]
a5=i.e
a6=a3.e
a7=a4.e
g=i.f
f=i.r
a8=a3.f
a9=a3.r
b0=a4.f
b1=a4.r
for(e3=a5.length,j=a6.length,a1=a7.length,e=0;e<t;++e){d=B.a.a_(e,f)
b2=B.a.a_(e,a9)
b3=B.a.a_(e,b1)
if(!(d<e3))return A.a(a5,d)
c=a5[d]
if(!(b2<j))return A.a(a6,b2)
b4=a6[b2]
if(!(b3<a1))return A.a(a7,b3)
b5=a7[b3]
for(b=0;b<r;++b){a=B.a.a_(b,g)
b6=B.a.a_(b,a8)
b7=B.a.a_(b,b0)
if(!(a<c.length))return A.a(c,a)
b8=c[a]
if(!(b6<b4.length))return A.a(b4,b6)
b9=b4[b6]
if(!(b7<b5.length))return A.a(b5,b7)
c0=b5[b7]
if(a2){a0=b8<<8>>>0
c1=b9-128
c2=c0-128
c3=B.a.j(a0+359*c2,8)
b8=B.a.J((c3&2147483647)-((c3&2147483648)>>>0),0,255)
c3=B.a.j(a0-88*c1-183*c2,8)
b9=B.a.J((c3&2147483647)-((c3&2147483648)>>>0),0,255)
c3=B.a.j(a0+454*c1,8)
c0=B.a.J((c3&2147483647)-((c3&2147483648)>>>0),0,255)}k.$5(b,e,b8,b9,c0)}}break
case 4:a1=e4.c
if(a1==null)throw A.f(A.n("Unsupported color mode (4 components)"))
a1=a1.d===0
if(0>=j)return A.a(e3,0)
i=e3[0]
if(1>=j)return A.a(e3,1)
a3=e3[1]
if(2>=j)return A.a(e3,2)
a4=e3[2]
if(3>=j)return A.a(e3,3)
c4=e3[3]
a5=i.e
a6=a3.e
a7=a4.e
c5=c4.e
g=i.f
f=i.r
a8=a3.f
a9=a3.r
b0=a4.f
b1=a4.r
c6=c4.f
c7=c4.r
for(e3=a5.length,j=a6.length,c3=a7.length,c8=c5.length,e=0;e<t;++e){d=B.a.a_(e,f)
b2=B.a.a_(e,a9)
b3=B.a.a_(e,b1)
c9=B.a.a_(e,c7)
if(!(d<e3))return A.a(a5,d)
c=a5[d]
if(!(b2<j))return A.a(a6,b2)
b4=a6[b2]
if(!(b3<c3))return A.a(a7,b3)
b5=a7[b3]
if(!(c9<c8))return A.a(c5,c9)
d0=c5[c9]
for(b=0;b<r;++b){a=B.a.a_(b,g)
b6=B.a.a_(b,a8)
b7=B.a.a_(b,b0)
d1=B.a.a_(b,c6)
if(a1){if(!(a<c.length))return A.a(c,a)
d2=c[a]
if(!(b6<b4.length))return A.a(b4,b6)
d3=b4[b6]
if(!(b7<b5.length))return A.a(b5,b7)
a0=b5[b7]
if(!(d1<d0.length))return A.a(d0,d1)
d4=d0[d1]}else{if(!(a<c.length))return A.a(c,a)
a0=c[a]
if(!(b6<b4.length))return A.a(b4,b6)
c1=b4[b6]
if(!(b7<b5.length))return A.a(b5,b7)
c2=b5[b7]
if(!(d1<d0.length))return A.a(d0,d1)
d4=d0[d1]
d5=c2-128
d6=c1-128
d7=a0<<8>>>0
d8=B.a.j(d7+359*d5,8)
d2=255-B.a.J((d8&2147483647)-((d8&2147483648)>>>0),0,255)
d8=B.a.j(d7-88*d6-183*d5,8)
d3=255-B.a.J((d8&2147483647)-((d8&2147483648)>>>0),0,255)
d8=B.a.j(d7+454*d6,8)
a0=255-B.a.J((d8&2147483647)-((d8&2147483648)>>>0),0,255)}d8=B.a.j(d2*d4,8)
d9=B.a.j(d3*d4,8)
e0=B.a.j(a0*d4,8)
k.$5(b,e,(d8&2147483647)-((d8&2147483648)>>>0),(d9&2147483647)-((d9&2147483648)>>>0),(e0&2147483647)-((e0&2147483648)>>>0))}}break
default:throw A.f(A.n("Unsupported color mode"))}return n},
jt:function jt(a,b){this.a=a
this.b=b},
ju:function ju(a,b,c){this.a=a
this.b=b
this.c=c},
jv:function jv(a,b){this.a=a
this.b=b},
jw:function jw(a){this.a=a},
jx:function jx(a,b){this.a=a
this.b=b},
jy:function jy(a,b,c){this.a=a
this.b=b
this.c=c},
jz:function jz(a,b){this.a=a
this.b=b},
hS:function hS(){this.d=null},
bA:function bA(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.y=_.x=_.w=_.r=_.f=_.e=$},
lo(){var t=A.P(4,null,!1,u.bC),s=A.j([],u.f8),r=u.eC,q=J.k_(0,r)
r=J.k_(0,r)
return new A.hU(new A.bw(A.D(u.N,u.P)),t,s,q,r,A.j([],u.eB))},
hU:function hU(a,b,c,d,e,f){var _=this
_.b=_.a=$
_.r=_.e=_.d=_.c=null
_.w=a
_.x=b
_.y=c
_.z=d
_.Q=e
_.as=f},
dh:function dh(a){this.a=a
this.b=0},
fz:function fz(a,b){var _=this
_.e=_.d=_.c=_.b=null
_.r=_.f=0
_.x=_.w=$
_.y=a
_.z=b},
hW:function hW(){this.r=this.f=$},
fA:function fA(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.f=$
_.r=null
_.y=c
_.z=d
_.Q=e
_.as=f
_.at=g
_.ax=h
_.cx=_.CW=_.ch=_.ay=0
_.cy=$},
fy:function fy(){},
hT:function hT(a,b){this.a=a
this.b=b},
hV:function hV(a,b,c,d,e,f,g,h,i){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.f=_.e=null
_.w=_.r=$
_.x=e
_.y=f
_.z=g
_.Q=h
_.as=i
_.at=null
_.ax=0
_.ay=7},
d2:function d2(a,b){this.a=a
this.b=b},
eg:function eg(a,b){this.a=a
this.b=b},
eh:function eh(){},
fr:function fr(a,b,c,d,e,f,g,h,i){var _=this
_.y=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h
_.x=i},
li(){var t=u.N
return new A.fs(A.D(t,t),A.j([],u.dm),A.j([],u.t))},
bD:function bD(a,b){this.a=a
this.b=b},
fK:function fK(){},
fs:function fs(a,b,c){var _=this
_.c=_.b=_.a=0
_.d=-1
_.r=_.f=0
_.z=_.x=_.w=null
_.Q=""
_.at=null
_.ax=a
_.CW=1
_.cy=b
_.db=c},
fJ:function fJ(a){var _=this
_.a=a
_.c=_.b=0
_.d=$
_.e=0},
bE:function bE(a,b){this.a=a
this.b=b},
bF:function bF(a){this.b=this.a=0
this.e=a},
i6:function i6(a){this.b=this.a=null
this.c=a},
i7:function i7(){},
fM:function fM(){this.a=null},
fN:function fN(){this.a=null},
b4:function b4(){},
fQ:function fQ(){this.a=null},
fR:function fR(){this.a=null},
fU:function fU(){this.a=null},
fV:function fV(){this.a=null},
ej:function ej(a){this.b=a},
fT:function fT(){},
i8:function i8(){var _=this
_.w=_.r=_.f=_.e=$},
cl:function cl(a){this.a=a
this.c=null},
lC(a){var t=new A.fO(A.j([],u.l),A.D(u.p,u.fh))
t.fU(a)
return t},
kg(a,b,c,d){var t=a/255,s=b/255,r=c/255,q=d/255,p=s*(1-r),o=t*(1-q)
return B.b.h(B.b.J((2*t<r?2*s*t+p+o:q*r-2*(r-t)*(q-s)+p+o)*255,0,255))},
ia(a,b){if(b===0)return 0
return B.a.h(B.a.J(B.b.h(255*(1-(1-a/255)/(b/255))),0,255))},
ic(a,b){return B.a.h(B.a.J(a+b-255,0,255))},
ki(a,b){return B.a.h(B.a.J(255-(255-b)*(255-a),0,255))},
ib(a,b){if(b===255)return 255
return B.b.h(B.b.J(a/255/(1-b/255)*255,0,255))},
kj(a,b){var t=a/255,s=b/255,r=1-s
return B.b.aD(255*(r*s*t+s*(1-r*(1-t))))},
ke(a,b){var t=b/255,s=a/255
if(s<0.5)return B.b.aD(510*t*s)
else return B.b.aD(255*(1-2*(1-t)*(1-s)))},
kk(a,b){if(b<128)return A.ia(a,2*b)
else return A.ib(a,2*(b-128))},
kf(a,b){var t
if(b<128)return A.ic(a,2*b)
else{t=2*(b-128)
return t+a>255?255:a+t}},
kh(a,b){return b<128?Math.min(a,2*b):Math.max(a,2*(b-128))},
kd(a,b){return B.b.aD(b+a-2*b*a/255)},
ay(a,b,c){var t,s,r
if(a==null)t=0
else{t=a.length
if(c===1){if(!(b>=0&&b<t))return A.a(a,b)
t=a[b]}else{if(!(b>=0&&b<t))return A.a(a,b)
s=a[b]
r=b+1
if(!(r<t))return A.a(a,r)
r=(s<<8|a[r])>>>8
t=r}}return t},
lD(b6,b7,b8,b9,c0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4=null,b5=A.D(u.p,u.fW)
for(t=c0.length,s=0;r=c0.length,s<r;c0.length===t||(0,A.a_)(c0),++s){q=c0[s]
b5.i(0,q.a,q)}if(b7===8)p=1
else p=b7===16?2:-1
o=A.R(b4,b4,B.f,0,B.j,b9,b4,0,r,b4,B.f,b8,!1)
if(p===-1)throw A.f(A.n("PSD: unsupported bit depth: "+A.z(b7)))
n=b5.k(0,0)
m=b5.k(0,1)
l=b5.k(0,2)
k=b5.k(0,-1)
j=A.j([0,0,0],u.t)
i=-p
for(t=o.a,t=t.gI(t),h=r>=5,g=r===4,f=r>=2,r=r>=4;t.F();){e=t.gM()
i+=p
switch(b6){case B.c2:e.sn(A.ay(n.c,i,p))
e.sp(A.ay(m.c,i,p))
e.sq(A.ay(l.c,i,p))
e.su(r?A.ay(k.c,i,p):255)
if(e.gu()!==0){e.sn((e.gn()+e.gu()-255)*255/e.gu())
e.sp((e.gp()+e.gu()-255)*255/e.gu())
e.sq((e.gq()+e.gu()-255)*255/e.gu())}break
case B.c4:d=A.ay(n.c,i,p)
c=A.ay(m.c,i,p)
b=A.ay(l.c,i,p)
a=r?A.ay(k.c,i,p):255
a0=((d*100>>>8)+16)/116
a1=(c-128)/500+a0
a2=a0-(b-128)/200
a3=Math.pow(a0,3)
a0=a3>0.008856?a3:(a0-0.13793103448275862)/7.787
a4=Math.pow(a1,3)
a1=a4>0.008856?a4:(a1-0.13793103448275862)/7.787
a5=Math.pow(a2,3)
a2=a5>0.008856?a5:(a2-0.13793103448275862)/7.787
a1=a1*95.047/100
a0=a0*100/100
a2=a2*108.883/100
a6=a1*3.240454836+a0*-1.53713885+a2*-0.498531547
a7=a1*-0.96926639+a0*1.87601093+a2*0.041556082
a8=a1*0.05564342+a0*-0.20402585+a2*1.05722516
a6=a6>0.0031308?1.055*Math.pow(a6,0.4166666666666667)-0.055:12.92*a6
a7=a7>0.0031308?1.055*Math.pow(a7,0.4166666666666667)-0.055:12.92*a7
a8=a8>0.0031308?1.055*Math.pow(a8,0.4166666666666667)-0.055:12.92*a8
a9=[B.b.aD(B.b.J(a6*255,0,255)),B.b.aD(B.b.J(a7*255,0,255)),B.b.aD(B.b.J(a8*255,0,255))]
e.sn(a9[0])
e.sp(a9[1])
e.sq(a9[2])
e.su(a)
break
case B.c1:b0=A.ay(n.c,i,p)
a=f?A.ay(k.c,i,p):255
e.sn(b0)
e.sp(b0)
e.sq(b0)
e.su(a)
break
case B.c3:b1=A.ay(n.c,i,p)
b2=A.ay(m.c,i,p)
a0=A.ay(l.c,i,p)
b3=A.ay(b5.k(0,g?-1:3).c,i,p)
a=h?A.ay(k.c,i,p):255
A.mf(255-b1,255-b2,255-a0,255-b3,j)
e.sn(j[0])
e.sp(j[1])
e.sq(j[2])
e.su(a)
break
default:throw A.f(A.n("Unhandled color mode: "+A.z(b6)))}}return o},
aY:function aY(a,b){this.a=a
this.b=b},
fO:function fO(a,b){var _=this
_.b=_.a=0
_.d=_.c=null
_.e=$
_.r=_.f=null
_.w=a
_.x=$
_.y=null
_.z=b
_.as=$
_.ay=_.ax=_.at=null},
fP:function fP(){},
fS:function fS(a,b,c){var _=this
_.b=_.a=null
_.f=_.e=_.d=_.c=$
_.r=null
_.as=_.y=_.w=$
_.ay=a
_.ch=b
_.cx=null
_.cy=c},
nH(a,b){var t
switch(a){case"lsct":t=b.c-b.d
b.l()
if(t>=12){if(b.ah(4)!=="8BIM")A.aA(A.n("Invalid key in layer additional data"))
b.ah(4)}if(t>=16)b.l()
return new A.fT()
default:return new A.ej(b)}},
d3:function d3(){},
i9:function i9(){this.a=null},
fW:function fW(){},
d6:function d6(a,b,c){this.a=a
this.b=b
this.c=c},
ar:function ar(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
d4:function d4(){var _=this
_.Q=_.z=_.y=_.f=_.d=_.b=_.a=0},
d5:function d5(a){var _=this
_.b=0
_.c=a
_.Q=_.r=_.f=0},
ek:function ek(){this.y=this.b=this.a=0},
bl(a,b){var t,s=a>>>8
if(!(s<256))return A.a(B.Q,s)
s=B.Q[s]
t=b>>>8
if(!(t<256))return A.a(B.Q,t)
return(s<<17|B.Q[t]<<16|B.Q[a&255]<<1|B.Q[b&255])>>>0},
aO:function aO(a){var _=this
_.a=a
_.b=0
_.c=!1
_.d=0
_.e=!1
_.f=0
_.r=!1},
id:function id(){this.b=this.a=null},
eq:function eq(a){var _=this
_.b=_.a=0
_.c=a
_.Q=_.z=_.y=_.x=_.f=_.e=0
_.as=null
_.ax=0},
as:function as(a,b){this.a=a
this.b=b},
ih:function ih(){this.a=null
this.b=$},
ii:function ii(a){this.a=a
this.c=this.b=0},
h0:function h0(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.f=e},
km(a,b,c){var t=new A.ik(b,a),s=u.I
t.e=A.P(b,null,!1,s)
t.f=A.P(b,null,!1,s)
return t},
ik:function ik(a,b){var _=this
_.a=a
_.c=b
_.d=0
_.f=_.e=null
_.r=$
_.x=_.w=null
_.y=0
_.z=2
_.as=0
_.at=null},
h1:function h1(a,b,c,d){var _=this
_.a=a
_.c=_.b=0
_.d=b
_.w=_.r=_.f=_.e=1
_.x=c
_.y=d
_.z=!1
_.Q=1
_.at=_.as=$
_.ch=_.ay=0
_.cx=_.CW=null
_.db=_.cy=$
_.dy=1
_.fx=_.fr=0
_.id=null
_.k3=_.k2=_.k1=$},
cn:function cn(a,b){this.a=a
this.b=b},
a5:function a5(a,b){this.a=a
this.b=b},
aP:function aP(a,b){this.a=a
this.b=b},
h2:function h2(a){var _=this
_.b=_.a=0
_.d=null
_.f=a},
lu(){return new A.i1(new Uint8Array(4096))},
i1:function i1(a){var _=this
_.a=9
_.d=_.c=_.b=0
_.w=_.r=_.f=_.e=$
_.x=a
_.z=_.y=$
_.Q=null
_.as=$},
ij:function ij(){this.a=null
this.c=$},
ko(a,b){var t=new Int32Array(4),s=new Int32Array(4),r=new Int8Array(4),q=new Int8Array(4),p=A.P(8,null,!1,u.eW),o=A.P(4,null,!1,u.dP)
return new A.iq(a,b,new A.iw(),new A.iz(),new A.is(t,s),new A.iB(r,q),p,o,new Uint8Array(4))},
lM(a,b,c){if(c===0)if(a===0)return b===0?6:5
else return b===0?4:0
return c},
iq:function iq(a,b,c,d,e,f,g,h,i){var _=this
_.a=a
_.b=b
_.c=$
_.d=null
_.e=$
_.f=c
_.r=d
_.w=e
_.x=f
_.as=_.Q=_.z=_.y=0
_.ax=_.at=null
_.ch=_.ay=$
_.cx=_.CW=null
_.cy=$
_.db=g
_.dy=h
_.fr=null
_.fy=_.fx=$
_.go=null
_.id=i
_.p3=_.p2=_.p1=_.ok=_.k4=_.k3=_.k2=_.k1=$
_.R8=_.p4=null
_.x2=_.x1=_.to=_.ry=_.rx=_.RG=$
_.xr=null
_.y2=_.y1=0
_.co=$
_.c1=null
_.dF=$
_.dG=_.f2=null
_.dH=$},
iC:function iC(){},
lK(a){var t=new A.eu(a)
t.b=254
t.c=0
t.d=-8
return t},
eu:function eu(a){var _=this
_.a=a
_.d=_.c=_.b=$
_.e=!1},
E(a,b,c){return B.a.aq(B.a.j(a+2*b+c+2,2),32)},
nZ(a){var t,s=A.j([A.E(J.c(a.a,a.d+-33),J.c(a.a,a.d+-32),J.c(a.a,a.d+-31)),A.E(J.c(a.a,a.d+-32),J.c(a.a,a.d+-31),J.c(a.a,a.d+-30)),A.E(J.c(a.a,a.d+-31),J.c(a.a,a.d+-30),J.c(a.a,a.d+-29)),A.E(J.c(a.a,a.d+-30),J.c(a.a,a.d+-29),J.c(a.a,a.d+-28))],u.t)
for(t=0;t<4;++t)a.bR(t*32,4,s)},
nR(a){var t=J.c(a.a,a.d+-33),s=J.c(a.a,a.d+-1),r=J.c(a.a,a.d+31),q=J.c(a.a,a.d+63),p=J.c(a.a,a.d+95),o=A.o(a,null,0),n=o.cz(),m=A.E(t,s,r)
n.$flags&2&&A.b(n)
if(0>=n.length)return A.a(n,0)
n[0]=16843009*m
o.d+=32
m=o.cz()
n=A.E(s,r,q)
m.$flags&2&&A.b(m)
if(0>=m.length)return A.a(m,0)
m[0]=16843009*n
o.d+=32
n=o.cz()
m=A.E(r,q,p)
n.$flags&2&&A.b(n)
if(0>=n.length)return A.a(n,0)
n[0]=16843009*m
o.d+=32
m=o.cz()
n=A.E(q,p,p)
m.$flags&2&&A.b(m)
if(0>=m.length)return A.a(m,0)
m[0]=16843009*n},
nP(a){var t,s,r,q
for(t=4,s=0;s<4;++s)t+=J.c(a.a,a.d+(s-32))+J.c(a.a,a.d+(-1+s*32))
t=B.a.j(t,3)
for(s=0;s<4;++s){r=a.a
q=a.d+s*32
J.b9(r,q,q+4,t)}},
kp(a,b){var t,s,r,q,p,o,n=255-J.c(a.a,a.d+-33)
for(t=0,s=0;s<b;++s){r=n+J.c(a.a,a.d+(t-1))
for(q=0;q<b;++q){p=$.aB()
o=r+J.c(a.a,a.d+(-32+q))
if(!(o>=0&&o<766))return A.a(p,o)
o=p[o]
J.x(a.a,a.d+(t+q),o)}t+=32}},
nX(a){A.kp(a,4)},
nY(a){A.kp(a,8)},
nW(a){A.kp(a,16)},
nV(a){var t,s=J.c(a.a,a.d+-1),r=J.c(a.a,a.d+31),q=J.c(a.a,a.d+63),p=J.c(a.a,a.d+95),o=J.c(a.a,a.d+-33),n=J.c(a.a,a.d+-32),m=J.c(a.a,a.d+-31),l=J.c(a.a,a.d+-30),k=J.c(a.a,a.d+-29)
a.i(0,96,A.E(r,q,p))
t=A.E(s,r,q)
a.i(0,97,t)
a.i(0,64,t)
t=A.E(o,s,r)
a.i(0,98,t)
a.i(0,65,t)
a.i(0,32,t)
t=A.E(n,o,s)
a.i(0,99,t)
a.i(0,66,t)
a.i(0,33,t)
a.i(0,0,t)
t=A.E(m,n,o)
a.i(0,67,t)
a.i(0,34,t)
a.i(0,1,t)
t=A.E(l,m,n)
a.i(0,35,t)
a.i(0,2,t)
a.i(0,3,A.E(k,l,m))},
nU(a){var t,s=J.c(a.a,a.d+-32),r=J.c(a.a,a.d+-31),q=J.c(a.a,a.d+-30),p=J.c(a.a,a.d+-29),o=J.c(a.a,a.d+-28),n=J.c(a.a,a.d+-27),m=J.c(a.a,a.d+-26),l=J.c(a.a,a.d+-25)
a.i(0,0,A.E(s,r,q))
t=A.E(r,q,p)
a.i(0,32,t)
a.i(0,1,t)
t=A.E(q,p,o)
a.i(0,64,t)
a.i(0,33,t)
a.i(0,2,t)
t=A.E(p,o,n)
a.i(0,96,t)
a.i(0,65,t)
a.i(0,34,t)
a.i(0,3,t)
t=A.E(o,n,m)
a.i(0,97,t)
a.i(0,66,t)
a.i(0,35,t)
t=A.E(n,m,l)
a.i(0,98,t)
a.i(0,67,t)
a.i(0,99,A.E(m,l,l))},
o0(a){var t=J.c(a.a,a.d+-1),s=J.c(a.a,a.d+31),r=J.c(a.a,a.d+63),q=J.c(a.a,a.d+-33),p=J.c(a.a,a.d+-32),o=J.c(a.a,a.d+-31),n=J.c(a.a,a.d+-30),m=J.c(a.a,a.d+-29),l=B.a.aq(B.a.j(q+p+1,1),32)
a.i(0,65,l)
a.i(0,0,l)
l=B.a.aq(B.a.j(p+o+1,1),32)
a.i(0,66,l)
a.i(0,1,l)
l=B.a.aq(B.a.j(o+n+1,1),32)
a.i(0,67,l)
a.i(0,2,l)
a.i(0,3,B.a.aq(B.a.j(n+m+1,1),32))
a.i(0,96,A.E(r,s,t))
a.i(0,64,A.E(s,t,q))
l=A.E(t,q,p)
a.i(0,97,l)
a.i(0,32,l)
l=A.E(q,p,o)
a.i(0,98,l)
a.i(0,33,l)
l=A.E(p,o,n)
a.i(0,99,l)
a.i(0,34,l)
a.i(0,35,A.E(o,n,m))},
o_(a){var t,s=J.c(a.a,a.d+-32),r=J.c(a.a,a.d+-31),q=J.c(a.a,a.d+-30),p=J.c(a.a,a.d+-29),o=J.c(a.a,a.d+-28),n=J.c(a.a,a.d+-27),m=J.c(a.a,a.d+-26),l=J.c(a.a,a.d+-25)
a.i(0,0,B.a.aq(B.a.j(s+r+1,1),32))
t=B.a.aq(B.a.j(r+q+1,1),32)
a.i(0,64,t)
a.i(0,1,t)
t=B.a.aq(B.a.j(q+p+1,1),32)
a.i(0,65,t)
a.i(0,2,t)
t=B.a.aq(B.a.j(p+o+1,1),32)
a.i(0,66,t)
a.i(0,3,t)
a.i(0,32,A.E(s,r,q))
t=A.E(r,q,p)
a.i(0,96,t)
a.i(0,33,t)
t=A.E(q,p,o)
a.i(0,97,t)
a.i(0,34,t)
t=A.E(p,o,n)
a.i(0,98,t)
a.i(0,35,t)
a.i(0,67,A.E(o,n,m))
a.i(0,99,A.E(n,m,l))},
nS(a){var t,s=J.c(a.a,a.d+-1),r=J.c(a.a,a.d+31),q=J.c(a.a,a.d+63),p=J.c(a.a,a.d+95)
a.i(0,0,B.a.aq(B.a.j(s+r+1,1),32))
t=B.a.aq(B.a.j(r+q+1,1),32)
a.i(0,32,t)
a.i(0,2,t)
t=B.a.aq(B.a.j(q+p+1,1),32)
a.i(0,64,t)
a.i(0,34,t)
a.i(0,1,A.E(s,r,q))
t=A.E(r,q,p)
a.i(0,33,t)
a.i(0,3,t)
t=A.E(q,p,p)
a.i(0,65,t)
a.i(0,35,t)
a.i(0,99,p)
a.i(0,98,p)
a.i(0,97,p)
a.i(0,96,p)
a.i(0,66,p)
a.i(0,67,p)},
nQ(a){var t=J.c(a.a,a.d+-1),s=J.c(a.a,a.d+31),r=J.c(a.a,a.d+63),q=J.c(a.a,a.d+95),p=J.c(a.a,a.d+-33),o=J.c(a.a,a.d+-32),n=J.c(a.a,a.d+-31),m=J.c(a.a,a.d+-30),l=B.a.aq(B.a.j(t+p+1,1),32)
a.i(0,34,l)
a.i(0,0,l)
l=B.a.aq(B.a.j(s+t+1,1),32)
a.i(0,66,l)
a.i(0,32,l)
l=B.a.aq(B.a.j(r+s+1,1),32)
a.i(0,98,l)
a.i(0,64,l)
a.i(0,96,B.a.aq(B.a.j(q+r+1,1),32))
a.i(0,3,A.E(o,n,m))
a.i(0,2,A.E(p,o,n))
l=A.E(t,p,o)
a.i(0,35,l)
a.i(0,1,l)
l=A.E(s,t,p)
a.i(0,67,l)
a.i(0,33,l)
l=A.E(r,s,t)
a.i(0,99,l)
a.i(0,65,l)
a.i(0,97,A.E(q,r,s))},
ob(a){var t
for(t=0;t<16;++t)a.bd(t*32,16,a,-32)},
o9(a){var t,s,r,q,p
for(t=0,s=16;s>0;--s){r=J.c(a.a,a.d+(t-1))
q=a.a
p=a.d+t
J.b9(q,p,p+16,r)
t+=32}},
iu(a,b){var t,s,r
for(t=0;t<16;++t){s=b.a
r=b.d+t*32
J.b9(s,r,r+16,a)}},
o1(a){var t,s
for(t=16,s=0;s<16;++s)t+=J.c(a.a,a.d+(-1+s*32))+J.c(a.a,a.d+(s-32))
A.iu(B.a.j(t,5),a)},
o3(a){var t,s
for(t=8,s=0;s<16;++s)t+=J.c(a.a,a.d+(-1+s*32))
A.iu(B.a.j(t,4),a)},
o2(a){var t,s
for(t=8,s=0;s<16;++s)t+=J.c(a.a,a.d+(s-32))
A.iu(B.a.j(t,4),a)},
o4(a){A.iu(128,a)},
oc(a){var t
for(t=0;t<8;++t)a.bd(t*32,8,a,-32)},
oa(a){var t,s,r,q,p
for(t=0,s=0;s<8;++s){r=J.c(a.a,a.d+(t-1))
q=a.a
p=a.d+t
J.b9(q,p,p+8,r)
t+=32}},
iv(a,b){var t,s,r
for(t=0;t<8;++t){s=b.a
r=b.d+t*32
J.b9(s,r,r+8,a)}},
o5(a){var t,s
for(t=8,s=0;s<8;++s)t+=J.c(a.a,a.d+(s-32))+J.c(a.a,a.d+(-1+s*32))
A.iv(B.a.j(t,4),a)},
o6(a){var t,s
for(t=4,s=0;s<8;++s)t+=J.c(a.a,a.d+(s-32))
A.iv(B.a.j(t,3),a)},
o7(a){var t,s
for(t=4,s=0;s<8;++s)t+=J.c(a.a,a.d+(-1+s*32))
A.iv(B.a.j(t,3),a)},
o8(a){A.iv(128,a)},
bH(a,b,c,d,e){var t=b+c+d*32,s=J.c(a.a,a.d+t)+B.a.j(e,3)
if(!((s&-256)>>>0===0))s=s<0?0:255
a.i(0,t,s)},
it(a,b,c,d,e){A.bH(a,0,0,b,c+d)
A.bH(a,0,1,b,c+e)
A.bH(a,0,2,b,c-e)
A.bH(a,0,3,b,c-d)},
nT(){var t,s,r,q
if(!$.lL){for(t=-255;t<=255;++t){s=$.hp()
r=255+t
q=t<0?-t:t
s.$flags&2&&A.b(s)
s[r]=q
q=$.jG()
s=B.a.j(s[r],1)
q.$flags&2&&A.b(q)
q[r]=s}for(t=-1020;t<=1020;++t){s=$.jH()
if(t<-128)r=-128
else r=t>127?127:t
s.$flags&2&&A.b(s)
s[1020+t]=r}for(t=-112;t<=112;++t){s=$.jI()
if(t<-16)r=-16
else r=t>15?15:t
s.$flags&2&&A.b(s)
s[112+t]=r}for(t=-255;t<=510;++t){s=$.aB()
if(t<0)r=0
else r=t>255?255:t
s.$flags&2&&A.b(s)
s[255+t]=r}$.lL=!0}},
ir:function ir(){},
nO(){var t,s=J.ag(3,u.D)
for(t=0;t<3;++t)s[t]=new Uint8Array(11)
return new A.et(s)},
os(){var t,s,r,q,p=new Uint8Array(3),o=J.ag(4,u.B)
for(t=u.dd,s=0;s<4;++s){r=J.ag(8,t)
for(q=0;q<8;++q)r[q]=A.nO()
o[s]=r}B.e.aB(p,0,3,255)
return new A.iA(p,o)},
iw:function iw(){this.d=$},
iz:function iz(){},
iB:function iB(a,b){var _=this
_.b=_.a=!1
_.c=!0
_.d=a
_.e=b},
et:function et(a){this.a=a},
iA:function iA(a,b){this.a=a
this.b=b},
is:function is(a,b){var _=this
_.a=$
_.b=null
_.d=_.c=$
_.e=a
_.f=b},
bq:function bq(){var _=this
_.b=_.a=0
_.c=!1
_.d=0},
ew:function ew(){this.b=this.a=0},
h9:function h9(a,b,c){this.a=a
this.b=b
this.c=c},
ex:function ex(a,b){var _=this
_.a=a
_.b=$
_.c=b
_.e=_.d=null
_.f=$},
ey:function ey(a,b,c){this.a=a
this.b=b
this.c=c},
kq(a,b){var t,s=A.j([],u.F),r=A.j([],u.R),q=new Uint32Array(2),p=new A.h7(a,q)
q=p.e=J.V(B.o.gB(q),0,null)
t=a.G()
q.$flags&2&&A.b(q)
if(0>=q.length)return A.a(q,0)
q[0]=t
t=a.G()
q.$flags&2&&A.b(q)
if(1>=q.length)return A.a(q,1)
q[1]=t
t=a.G()
q.$flags&2&&A.b(q)
if(2>=q.length)return A.a(q,2)
q[2]=t
t=a.G()
q.$flags&2&&A.b(q)
if(3>=q.length)return A.a(q,3)
q[3]=t
t=a.G()
q.$flags&2&&A.b(q)
if(4>=q.length)return A.a(q,4)
q[4]=t
t=a.G()
q.$flags&2&&A.b(q)
if(5>=q.length)return A.a(q,5)
q[5]=t
t=a.G()
q.$flags&2&&A.b(q)
if(6>=q.length)return A.a(q,6)
q[6]=t
t=a.G()
q.$flags&2&&A.b(q)
if(7>=q.length)return A.a(q,7)
q[7]=t
p.b=!1
return new A.ev(p,b,s,r)},
bI(a,b){return B.a.j(a+B.a.O(1,b)-1,b)},
ev:function ev(a,b,c,d){var _=this
_.b=a
_.c=b
_.d=null
_.w=_.r=_.f=0
_.x=null
_.Q=_.z=_.y=0
_.as=null
_.at=0
_.ax=c
_.ay=null
_.ch=d
_.CW=0
_.cx=null
_.cy=$
_.db=0
_.dx=null
_.fr=_.dy=0},
ft:function ft(a,b,c,d){var _=this
_.b=a
_.c=b
_.d=null
_.w=_.r=_.f=0
_.x=null
_.Q=_.z=_.y=0
_.as=null
_.at=0
_.ax=c
_.ay=null
_.ch=d
_.CW=0
_.cx=null
_.cy=$
_.db=0
_.dx=null
_.fr=_.dy=0},
h7:function h7(a,b){var _=this
_.a=0
_.b=!0
_.c=a
_.d=b
_.e=$},
ix:function ix(a,b){this.a=a
this.b=b},
br(a,b){return((a^b)>>>1&2139062143)+((a&b)>>>0)},
cp(a){if(a<0)return 0
if(a>255)return 255
return a},
iy(a,b,c){return Math.abs(b-c)-Math.abs(a-c)},
od(a,b,c){return 4278190080},
oe(a,b,c){return a},
oj(a,b,c){if(!(c>=0&&c<b.length))return A.a(b,c)
return b[c]},
ok(a,b,c){var t=c+1
if(!(t>=0&&t<b.length))return A.a(b,t)
return b[t]},
ol(a,b,c){var t=c-1
if(!(t>=0&&t<b.length))return A.a(b,t)
return b[t]},
om(a,b,c){var t,s,r=b.length
if(!(c>=0&&c<r))return A.a(b,c)
t=b[c]
s=c+1
if(!(s<r))return A.a(b,s)
return A.br(A.br(a,b[s]),t)},
on(a,b,c){var t=c-1
if(!(t>=0&&t<b.length))return A.a(b,t)
return A.br(a,b[t])},
oo(a,b,c){if(!(c>=0&&c<b.length))return A.a(b,c)
return A.br(a,b[c])},
op(a,b,c){var t=c-1,s=b.length
if(!(t>=0&&t<s))return A.a(b,t)
t=b[t]
if(!(c>=0&&c<s))return A.a(b,c)
return A.br(t,b[c])},
oq(a,b,c){var t,s,r=b.length
if(!(c>=0&&c<r))return A.a(b,c)
t=b[c]
s=c+1
if(!(s<r))return A.a(b,s)
return A.br(t,b[s])},
of(a,b,c){var t,s,r=c-1,q=b.length
if(!(r>=0&&r<q))return A.a(b,r)
r=b[r]
if(!(c>=0&&c<q))return A.a(b,c)
t=b[c]
s=c+1
if(!(s<q))return A.a(b,s)
s=b[s]
return A.br(A.br(a,r),A.br(t,s))},
og(a,b,c){var t,s,r=b.length
if(!(c>=0&&c<r))return A.a(b,c)
t=b[c]
s=c-1
if(!(s>=0&&s<r))return A.a(b,s)
s=b[s]
return A.iy(t>>>24,a>>>24,s>>>24)+A.iy(t>>>16&255,a>>>16&255,s>>>16&255)+A.iy(t>>>8&255,a>>>8&255,s>>>8&255)+A.iy(t&255,a&255,s&255)<=0?t:a},
oh(a,b,c){var t,s,r=b.length
if(!(c>=0&&c<r))return A.a(b,c)
t=b[c]
s=c-1
if(!(s>=0&&s<r))return A.a(b,s)
s=b[s]
return(A.cp((a>>>24)+(t>>>24)-(s>>>24))<<24|A.cp((a>>>16&255)+(t>>>16&255)-(s>>>16&255))<<16|A.cp((a>>>8&255)+(t>>>8&255)-(s>>>8&255))<<8|A.cp((a&255)+(t&255)-(s&255)))>>>0},
oi(a,b,c){var t,s,r,q,p,o=b.length
if(!(c>=0&&c<o))return A.a(b,c)
t=b[c]
s=c-1
if(!(s>=0&&s<o))return A.a(b,s)
s=b[s]
r=A.br(a,t)
t=r>>>24
o=r>>>16&255
q=r>>>8&255
p=r>>>0&255
return(A.cp(t+B.a.Y(t-(s>>>24),2))<<24|A.cp(o+B.a.Y(o-(s>>>16&255),2))<<16|A.cp(q+B.a.Y(q-(s>>>8&255),2))<<8|A.cp(p+B.a.Y(p-(s&255),2)))>>>0},
co:function co(a,b){this.a=a
this.b=b},
h8:function h8(a){var _=this
_.a=a
_.c=_.b=0
_.d=null
_.e=0},
iD:function iD(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.f=_.e=_.d=0
_.r=1
_.w=!1
_.x=$
_.y=!1},
ez:function ez(){},
fu:function fu(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.r=_.f=$
_.w=1
_.y=_.x=$},
jT(a){var t,s=J.c4(a,u.gj)
for(t=0;t<a;++t)s[t]=new A.f8()
return new A.dA(s,0)},
ne(){var t,s,r=J.ag(5,u.fa)
for(t=0;t<5;++t)r[t]=A.jT(0)
s=J.ag(64,u.ak)
for(t=0;t<64;++t)s[t]=new A.f9()
return new A.dz(r,s)},
f8:function f8(){this.b=this.a=0},
f9:function f9(){this.b=this.a=0},
dA:function dA(a,b){this.a=a
this.b=b},
dz:function dz(a,b){var _=this
_.a=a
_.b=!1
_.c=0
_.e=_.d=!1
_.f=b},
dB:function dB(){var _=this
_.b=_.a=null
_.e=_.d=0},
fb:function fb(a){this.a=a
this.b=null},
df:function df(a,b){this.a=a
this.b=b},
dg:function dg(a,b){var _=this
_.b=_.a=0
_.c=null
_.e=_.d=!1
_.f=a
_.r=null
_.w=""
_.y=0
_.z=b
_.as=0
_.at=null
_.ch=_.ay=0},
dK:function dK(a,b){var _=this
_.b=_.a=0
_.c=null
_.e=_.d=!1
_.f=a
_.r=null
_.w=""
_.y=0
_.z=b
_.as=0
_.at=null
_.ch=_.ay=0},
iE:function iE(){this.b=this.a=null},
l5(a){return new A.bf(a.a,a.b,B.e.fA(a.c,0))},
fc:function fc(a,b){this.a=a
this.b=b},
bf:function bf(a,b,c){this.a=a
this.b=b
this.c=c},
R(a,b,c,d,e,f,g,h,i,j,k,l,m){var t,s=new A.bh(null,null,null,a,h,e,d,0)
B.c.A(s.gaA(),s)
s.c=g
if(b!=null)s.e=A.ds(b)
t=!1
if(j==null)if(m)t=s.gK()===B.w||s.gK()===B.y||s.gK()===B.z||s.gK()===B.f||s.gK()===B.l
s.e5(l,f,c,i,t?s.ha(c,k,i):j)
return s},
fg(a,b,c,d){var t,s,r,q,p=null,o=a.e
o=o==null?p:A.ds(o)
t=a.c
t=t==null?p:A.l5(t)
s=a.w
r=a.r
q=a.f
q=q==null?p:new A.aS(new Uint8Array(A.w(q.a)))
s=new A.bh(p,t,o,q,r,s,a.y,a.z)
s.fR(a,b,c,d)
return s},
bz(a,b,c){var t,s,r,q,p,o=null,n=a.a
n=n==null?o:n.bb(c)
t=a.e
t=t==null?o:A.ds(t)
s=a.c
s=s==null?o:A.l5(s)
r=a.w
q=a.r
p=a.f
p=p==null?o:new A.aS(new Uint8Array(A.w(p.a)))
r=new A.bh(n,s,t,p,q,r,a.y,a.z)
r.fQ(a,b,c)
return r},
f6:function f6(a,b){this.a=a
this.b=b},
bh:function bh(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=null
_.c=b
_.d=null
_.e=c
_.f=d
_.r=e
_.w=f
_.x=$
_.y=g
_.z=h},
hO:function hO(a,b){this.a=a
this.b=b},
hN:function hN(){},
af:function af(){},
nf(a,b,c){return new A.cR(new Uint16Array(a*b*c),a,b,c)},
cR:function cR(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
ng(a,b,c){return new A.cS(new Float32Array(a*b*c),a,b,c)},
cS:function cS(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
dD:function dD(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
dE:function dE(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
dF:function dF(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
dG:function dG(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
cT:function cT(a,b,c,d,e,f){var _=this
_.d=a
_.e=b
_.f=c
_.r=null
_.a=d
_.b=e
_.c=f},
cU:function cU(a,b,c,d,e){var _=this
_.d=a
_.e=b
_.a=c
_.b=d
_.c=e},
cV:function cV(a,b,c,d,e,f){var _=this
_.d=a
_.e=b
_.f=c
_.r=null
_.a=d
_.b=e
_.c=f},
nh(a,b,c){return new A.cW(new Uint32Array(a*b*c),a,b,c)},
cW:function cW(a,b,c,d){var _=this
_.d=a
_.a=b
_.b=c
_.c=d},
cX:function cX(a,b,c,d,e,f){var _=this
_.d=a
_.e=b
_.f=c
_.r=null
_.a=d
_.b=e
_.c=f},
lg(a,b,c){return new A.cY(new Uint8Array(a*b*c),null,a,b,c)},
cY:function cY(a,b,c,d,e){var _=this
_.d=a
_.e=b
_.a=c
_.b=d
_.c=e},
dL:function dL(a,b){this.a=a
this.b=b},
aN:function aN(){},
e5:function e5(a,b,c){this.c=a
this.a=b
this.b=c},
e6:function e6(a,b,c){this.c=a
this.a=b
this.b=c},
e7:function e7(a,b,c){this.c=a
this.a=b
this.b=c},
e8:function e8(a,b,c){this.c=a
this.a=b
this.b=c},
e9:function e9(a,b,c){this.c=a
this.a=b
this.b=c},
ea:function ea(a,b,c){this.c=a
this.a=b
this.b=c},
eb:function eb(a,b,c){this.c=a
this.a=b
this.b=c},
ec:function ec(a,b,c){this.c=a
this.a=b
this.b=c},
lx(a){return new A.aW(new Uint8Array(A.w(a.c)),a.a,a.b)},
aW:function aW(a,b,c){this.c=a
this.a=b
this.b=c},
k5(a){return new A.c9(-1,0,-a.c,a)},
c9:function c9(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
k6(a){return new A.ca(-1,0,-a.c,a)},
ca:function ca(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
k7(a){return new A.cb(-1,0,-a.c,a)},
cb:function cb(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
k8(a){return new A.cc(-1,0,-a.c,a)},
cc:function cc(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
k9(a){return new A.cd(-1,0,-a.c,a)},
cd:function cd(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
ka(a){return new A.ce(-1,0,-a.c,a)},
ce:function ce(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
aX(a,b,c,d,e){a.Z(b-1,c)
return new A.fH(a,b,b+d-1,c+e-1)},
fH:function fH(a,b,c,d){var _=this
_.a=a
_.b=b
_.d=c
_.e=d},
ed(a){return new A.cf(-1,0,0,-1,0,a)},
cf:function cf(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
kb(a){return new A.cg(-1,0,-a.c,a)},
cg:function cg(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
ee(a){return new A.ch(-1,0,0,-2,0,a)},
ch:function ch(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
kc(a){return new A.ci(-1,0,-a.c,a)},
ci:function ci(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
ef(a){return new A.cj(-1,0,0,-(a.c<<2>>>0),a)},
cj:function cj(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
i5(a){return new A.ck(-1,0,-a.c,a)},
ck:function ck(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
G:function G(){},
q1(a,b){switch(b.a){case 0:A.hm(a)
break
case 1:A.q3(a)
break
case 2:A.q2(a)
break}return a},
q3(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e=null,d=a.gaA().length
for(t=u.g,s=0;s<d;++s){r=a.x
if(r===$)r=a.x=A.j([],t)
if(!(s<r.length))return A.a(r,s)
q=r[s]
p=q.a
o=p==null
n=o?e:p.a
if(n==null)n=0
m=o?e:p.b
if(m==null)m=0
l=B.a.Y(m,2)
p=a.a
if((p==null?e:p.gR())!=null)for(k=m-1,j=0;j<l;++j,--k)for(i=0;i<n;++i){p=q.a
h=p==null?e:p.L(i,j,e)
if(h==null)h=new A.G()
p=q.a
g=p==null?e:p.L(i,k,e)
if(g==null)g=new A.G()
f=h.gN()
h.sN(g.gN())
g.sN(f)}else for(k=m-1,j=0;j<l;++j,--k)for(i=0;i<n;++i){p=q.a
h=p==null?e:p.L(i,j,e)
if(h==null)h=new A.G()
p=q.a
g=p==null?e:p.L(i,k,e)
if(g==null)g=new A.G()
f=h.gn()
h.sn(g.gn())
g.sn(f)
f=h.gp()
h.sp(g.gp())
g.sp(f)
f=h.gq()
h.sq(g.gq())
g.sq(f)
f=h.gu()
h.su(g.gu())
g.su(f)}}return a},
hm(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=null,c=a.gaA().length
for(t=u.g,s=0;s<c;++s){r=a.x
if(r===$)r=a.x=A.j([],t)
if(!(s<r.length))return A.a(r,s)
q=r[s]
p=q.a
o=p==null
n=o?d:p.a
if(n==null)n=0
m=o?d:p.b
if(m==null)m=0
l=B.a.Y(n,2)
p=a.a
if((p==null?d:p.gR())!=null)for(k=n-1,j=0;j<m;++j)for(i=k,h=0;h<l;++h,--i){p=q.a
g=p==null?d:p.L(h,j,d)
if(g==null)g=new A.G()
p=q.a
f=p==null?d:p.L(i,j,d)
if(f==null)f=new A.G()
e=g.gN()
g.sN(f.gN())
f.sN(e)}else for(k=n-1,j=0;j<m;++j)for(i=k,h=0;h<l;++h,--i){p=q.a
g=p==null?d:p.L(h,j,d)
if(g==null)g=new A.G()
p=q.a
f=p==null?d:p.L(i,j,d)
if(f==null)f=new A.G()
e=g.gn()
g.sn(f.gn())
f.sn(e)
e=g.gp()
g.sp(f.gp())
f.sp(e)
e=g.gq()
g.sq(f.gq())
f.sq(e)
e=g.gu()
g.su(f.gu())
f.su(e)}}return a},
q2(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=null,b=a.gaA().length
for(t=u.g,s=0;s<b;++s){r=a.x
if(r===$)r=a.x=A.j([],t)
if(!(s<r.length))return A.a(r,s)
q=r[s]
p=q.a
o=p==null
n=o?c:p.a
if(n==null)n=0
m=o?c:p.b
if(m==null)m=0
l=B.a.Y(m,2)
if((o?c:p.gR())!=null)for(k=m-1,j=n-1,i=0;i<l;++i,--k)for(h=j,g=0;g<n;++g,--h){p=q.a
f=p==null?c:p.L(g,i,c)
if(f==null)f=new A.G()
p=q.a
e=p==null?c:p.L(h,k,c)
if(e==null)e=new A.G()
d=f.gN()
f.sN(e.gN())
e.sN(d)}else for(k=m-1,j=n-1,i=0;i<l;++i,--k)for(h=j,g=0;g<n;++g,--h){p=q.a
f=p==null?c:p.L(g,i,c)
if(f==null)f=new A.G()
p=q.a
e=p==null?c:p.L(h,k,c)
if(e==null)e=new A.G()
d=f.gn()
f.sn(e.gn())
e.sn(d)
d=f.gp()
f.sp(e.gp())
e.sp(d)
d=f.gq()
f.sq(e.gq())
e.sq(d)
d=f.gu()
f.su(e.gu())
e.su(d)}}return a},
hA:function hA(a,b){this.a=a
this.b=b},
n(a){return new A.hM(a)},
hM:function hM(a){this.a=a},
v(a,b,c,d){var t=J.S(a),s=t.gt(a)
t=c==null?t.gt(a):d+c
return new A.aa(a,d,Math.min(s,t),d,b)},
o(a,b,c){var t=a.a,s=a.d,r=a.b,q=J.ao(t),p=b==null?a.c:a.d+c+b
return new A.aa(t,r,Math.min(q,p),s+c,a.e)},
aa:function aa(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
e3(a,b){return new A.i4(a,new Uint8Array(b))},
i4:function i4(a,b){this.a=0
this.b=a
this.c=b},
d9:function d9(a,b){this.a=a
this.b=b},
qg(){if(typeof A.kF()=="function")A.aA(A.bQ("Attempting to rewrap a JS function."))
var t=function(a,b){return function(c,d){return a(b,c,d,arguments.length)}}(A.p3,A.kF())
t[$.kJ()]=A.kF()
v.G.soleVisionNormalize=t},
pO(a){var t
A:{if("+x"===a){t=B.cc
break A}if("-x"===a){t=B.cd
break A}if("+z"===a){t=B.ce
break A}if("-z"===a){t=B.aI
break A}t=null
break A}return t},
pw(a6,a7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5=null
A.j0(a6)
A.j0(a7)
t={}
try{s=u.e.a(a6)
r=u.c.a(B.K.f0(A.b0(a7),a5))
l=u.N
q=A.D(l,l)
p=J.c(r,"materialRenames")
if(u.f.b(p))p.aT(0,new A.j8(q))
l=new Uint8Array(A.w(s))
k=A.Q(J.c(r,"externalLengthMm"))
if(k==null)k=a5
j=A.pO(A.ku(J.c(r,"toe")))
A.Q(J.c(r,"authoredSizeEu"))
i=A.Q(J.c(r,"maxTextureSize"))
i=i==null?a5:B.b.h(i)
if(i==null)i=1024
h=A.Q(J.c(r,"jpegQuality"))
h=h==null?a5:B.b.h(h)
if(h==null)h=88
g=A.Q(J.c(r,"soleBandMm"))
if(g==null)g=a5
g=new A.hG(k,j,i,h,q,g)
h=u.s
f=A.j([],h)
e=A.m8(l)
A.pC(e)
d=A.ma(e,f)
l=l.length
c=A.m7(d,A.m2(e),l)
A.p2(d,e,f)
A.pD(d,g,f)
A.pH(d,g,f)
b=d.d3()
a=-(b[0]+b[3])/2
a0=-b[1]
a1=-b[2]
A.hj(d,A.j([1,0,0,0,1,0,0,0,1,a,a0,a1],u.n))
B.c.A(f,"moved the mesh so the heel-bottom-centre sits at the origin: x "+B.b.bn(-a*1000,1)+" mm, y "+B.b.bn(-a0*1000,1)+" mm and z "+B.b.bn(-a1*1000,1)+" mm off, now grounded and centred")
s=A.pR(d,e,A.pz(e,g,f),A.pA(e,d,g,f),f)
a2=A.m8(s)
g=s.length
a3=A.m7(A.ma(a2,A.j([],h)),A.m2(a2),g)
B.c.A(f,"file size "+A.ji(l)+" \u2192 "+A.ji(g))
o=new A.hF(s,f,c,a3)
t.ok=!0
t.bytes=o.a
t.changes=B.K.d4(o.b,a5)
t.before=B.K.d4(o.c,a5)
t.after=B.K.d4(o.d,a5)}catch(a4){l=A.kH(a4)
if(l instanceof A.a7){n=l
t.ok=!1
t.error=n.a}else{m=l
t.ok=!1
t.error=J.ac(m)}}return t},
j8:function j8(a){this.a=a},
nN(a){throw A.f(A.b5("Uint64List not supported on the web."))},
jO(a){var t=a.BYTES_PER_ELEMENT,s=A.aZ(0,null,B.a.au(a.byteLength,t))
return J.mK(B.e.gB(a),a.byteOffset+0*t,s*t)},
ni(a,b,c){return J.jL(a,b,c)},
io(a,b,c){var t=a.BYTES_PER_ELEMENT
c=A.aZ(b,c,B.a.au(a.byteLength,t))
return J.V(B.e.gB(a),a.byteOffset+b*t,(c-b)*t)},
lI(a,b){return J.aw(a,b,null)},
na(a){return J.kO(a,0,null)},
nb(a){return a.jO(0,0,null)},
p3(a,b,c,d){u.Z.a(a)
A.u(d)
if(d>=2)return a.$2(b,c)
if(d===1)return a.$1(b)
return a.$0()},
cv(a,b){var t,s,r=J.S(a),q=r.gt(a)
b^=4294967295
for(t=0;q>=8;){s=t+1
b=B.A[(b^r.k(a,t))&255]^b>>>8
t=s+1
b=B.A[(b^r.k(a,s))&255]^b>>>8
s=t+1
b=B.A[(b^r.k(a,t))&255]^b>>>8
t=s+1
b=B.A[(b^r.k(a,s))&255]^b>>>8
s=t+1
b=B.A[(b^r.k(a,t))&255]^b>>>8
t=s+1
b=B.A[(b^r.k(a,s))&255]^b>>>8
s=t+1
b=B.A[(b^r.k(a,t))&255]^b>>>8
t=s+1
b=B.A[(b^r.k(a,s))&255]^b>>>8
q-=8}if(q>0)do{s=t+1
b=B.A[(b^r.k(a,t))&255]^b>>>8
if(--q,q>0){t=s
continue}else break}while(!0)
return(b^4294967295)>>>0},
kA(a,b,c,d,e,f,g,h,i,j,k){var t,s,r,q,p,o,n,m
if(j==null)j=0
if(k==null)k=0
if(i==null)i=b.ga5()
if(h==null)h=b.gV()
if(e==null)e=a.ga5()<b.ga5()?a.ga5():b.ga5()
if(d==null)d=a.gV()<b.gV()?a.gV():b.gV()
t=c===B.a2
if(!t&&a.gcp())a=a.eY(a.gc2())
s=h/d
r=i/e
q=u.p
p=J.ag(d,q)
for(o=0;o<d;++o)p[o]=k+B.b.h(o*s)
n=J.ag(e,q)
for(m=0;m<e;++m)n[m]=j+B.b.h(m*r)
if(t)A.p8(b,a,f,g,e,d,n,p,null,B.aR)
else A.p4(b,a,f,g,e,d,n,p,c,!1,null,B.aR)
return a},
p8(a,b,c,d,e,f,g,a0,a1,a2){var t,s,r,q,p,o,n,m,l,k,j,i=b.ga5(),h=b.gV()
for(t=g.length,s=a0.length,r=null,q=0;q<f;++q)for(p=d+q,o=p>=h,n=0;n<e;++n){m=c+n
if(m>=i||o)continue
if(!(n<t))return A.a(g,n)
l=g[n]
if(!(q<s))return A.a(a0,q)
k=a0[q]
j=a.a
r=j==null?null:j.L(l,k,r)
if(r==null)r=new A.G()
b.bI(m,p,r)}},
p4(a,b,c,d,e,f,g,h,i,j,k,a0){var t,s,r,q,p,o,n,m,l
for(t=g.length,s=h.length,r=null,q=0;q<f;++q)for(p=d+q,o=0;o<e;++o){if(!(o<t))return A.a(g,o)
n=g[o]
if(!(q<s))return A.a(h,q)
m=h[q]
l=a.a
r=l==null?null:l.L(n,m,r)
if(r==null)r=new A.G()
A.q_(b,c+o,p,r,i,!1,k,a0)}},
q_(a7,a8,a9,b0,b1,b2,b3,b4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6
if(!a7.f4(a8,a9))return a7
if(b1===B.a2||a7.gcp())if(a7.f4(a8,a9)){a7.aJ(a8,a9).ac(b0)
return a7}t=b0.gaa()
s=b0.ga6()
r=b0.ga9()
q=b0.gt(b0)<4?1:b0.gU()
if(q===0)return a7
p=a7.aJ(a8,a9)
o=p.gaa()
n=p.ga6()
m=p.ga9()
l=p.gU()
switch(b1.a){case 0:return a7
case 1:break
case 2:t=Math.max(o,t)
s=Math.max(n,s)
r=Math.max(m,r)
break
case 3:t=1-(1-t)*(1-o)
s=1-(1-s)*(1-n)
r=1-(1-r)*(1-m)
break
case 4:k=q*l
j=1-l
i=1-q
h=t*j+o*i
g=s*j+n*i
f=r*j+m*i
i=B.b.J(q,0.01,1)
j=q<0
e=j?0:1
d=B.b.J(t/i*e,0,0.99)
e=B.b.J(q,0.01,1)
i=j?0:1
c=B.b.J(s/e*i,0,0.99)
i=B.b.J(q,0.01,1)
j=j?0:1
b=B.b.J(r/i*j,0,0.99)
j=o*q
i=n*q
e=m*q
a=k<t*l+j?0:1
a0=k<s*l+i?0:1
a1=k<r*l+e?0:1
t=(k+h)*(1-a)+(j/(1-d)+h)*a
s=(k+g)*(1-a0)+(i/(1-c)+g)*a0
r=(k+f)*(1-a1)+(e/(1-b)+f)*a1
break
case 5:t=o+t
s=n+s
r=m+r
break
case 6:t=Math.min(o,t)
s=Math.min(n,s)
r=Math.min(m,r)
break
case 7:t=o*t
s=n*s
r=m*r
break
case 8:t=t!==0?1-(1-o)/t:0
s=s!==0?1-(1-n)/s:0
r=r!==0?1-(1-m)/r:0
break
case 9:j=1-l
i=1-q
e=t*j
a2=o*i
t=2*o<l?2*t*o+e+a2:q*l-2*(l-o)*(q-t)+e+a2
e=s*j
a2=n*i
s=2*n<l?2*s*n+e+a2:q*l-2*(l-n)*(q-s)+e+a2
j=r*j
i=m*i
r=2*m<l?2*r*m+j+i:q*l-2*(l-m)*(q-r)+j+i
break
case 10:j=l===0
if(j)t=0
else{i=o/l
t=o*(q*i+2*t*(1-i))+t*(1-l)+o*(1-q)}if(j)s=0
else{i=n/l
s=n*(q*i+2*s*(1-i))+s*(1-l)+n*(1-q)}if(j)r=0
else{j=m/l
r=m*(q*j+2*r*(1-j))+r*(1-l)+m*(1-q)}break
case 11:j=2*t
i=1-l
e=1-q
a2=t*i
a3=o*e
t=j<q?j*o+a2+a3:q*l-2*(l-o)*(q-t)+a2+a3
j=2*s
a2=s*i
a3=n*e
s=j<q?j*n+a2+a3:q*l-2*(l-n)*(q-s)+a2+a3
j=2*r
i=r*i
e=m*e
r=j<q?j*m+i+e:q*l-2*(l-m)*(q-r)+i+e
break
case 12:t=Math.abs(t-o)
s=Math.abs(s-n)
r=Math.abs(r-m)
break
case 13:t=o-t
s=n-s
r=m-r
break
case 14:t=t!==0?o/t:0
s=s!==0?n/s:0
r=r!==0?m/r:0
break}a4=1-q
a5=q+l*a4
a6=a5>0?1/a5:0
p.saa((t*q+o*l*a4)*a6)
p.sa6((s*q+n*l*a4)*a6)
p.sa9((r*q+m*l*a4)*a6)
p.sU(a5)
return a7},
mh(a,b,c,d,e,f,g){var t,s=B.b.J(Math.min(d,e),0,a.ga5()-1),r=B.b.J(Math.min(f,g),0,a.gV()-1),q=B.b.J(Math.max(d,e),0,a.ga5()-1),p=B.b.J(Math.max(f,g),0,a.gV()-1),o=a.a.b4(0,s,r,q-s+1,p-r+1)
for(t=o.a;o.F();)t.ac(c)
return a},
n7(a5,a6,a7,a8,a9,b0,b1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=b1<16384,a4=a7>a9?a9:a7
for(t=1;t<=a4;)t=t<<1>>>0
t=t>>>1
s=t>>>1
r=A.j([0,0],u.t)
for(q=a5.length,p=t,t=s;t>=1;p=t,t=s){o=a6+b0*(a9-p)
n=b0*t
m=b0*p
l=a8*t
k=a8*p
for(j=(a7&t)>>>0!==0,i=a8*(a7-p),h=a6;h<=o;h+=m){g=h+i
for(f=h;f<=g;f+=k){e=f+l
d=f+n
c=d+l
if(a3){if(!(f>=0&&f<q))return A.a(a5,f)
b=a5[f]
if(!(d>=0&&d<q))return A.a(a5,d)
A.du(b,a5[d],r)
a=r[0]
a0=r[1]
if(!(e>=0&&e<q))return A.a(a5,e)
b=a5[e]
if(!(c>=0&&c<q))return A.a(a5,c)
A.du(b,a5[c],r)
a1=r[0]
a2=r[1]
A.du(a,a1,r)
b=r[0]
a5.$flags&2&&A.b(a5)
a5[f]=b
a5[e]=r[1]
A.du(a0,a2,r)
b=r[0]
a5.$flags&2&&A.b(a5)
a5[d]=b
a5[c]=r[1]}else{if(!(f>=0&&f<q))return A.a(a5,f)
b=a5[f]
if(!(d>=0&&d<q))return A.a(a5,d)
A.dv(b,a5[d],r)
a=r[0]
a0=r[1]
if(!(e>=0&&e<q))return A.a(a5,e)
b=a5[e]
if(!(c>=0&&c<q))return A.a(a5,c)
A.dv(b,a5[c],r)
a1=r[0]
a2=r[1]
A.dv(a,a1,r)
b=r[0]
a5.$flags&2&&A.b(a5)
a5[f]=b
a5[e]=r[1]
A.dv(a0,a2,r)
b=r[0]
a5.$flags&2&&A.b(a5)
a5[d]=b
a5[c]=r[1]}}if(j){d=f+n
if(a3){if(!(f>=0&&f<q))return A.a(a5,f)
b=a5[f]
if(!(d>=0&&d<q))return A.a(a5,d)
A.du(b,a5[d],r)
a=r[0]
b=r[1]
a5.$flags&2&&A.b(a5)
a5[d]=b}else{if(!(f>=0&&f<q))return A.a(a5,f)
b=a5[f]
if(!(d>=0&&d<q))return A.a(a5,d)
A.dv(b,a5[d],r)
a=r[0]
b=r[1]
a5.$flags&2&&A.b(a5)
a5[d]=b}a5.$flags&2&&A.b(a5)
if(!(f>=0&&f<q))return A.a(a5,f)
a5[f]=a}}if((a9&t)>>>0!==0){g=h+i
for(f=h;f<=g;f+=k){e=f+l
if(a3){if(!(f>=0&&f<q))return A.a(a5,f)
j=a5[f]
if(!(e>=0&&e<q))return A.a(a5,e)
A.du(j,a5[e],r)
a=r[0]
j=r[1]
a5.$flags&2&&A.b(a5)
a5[e]=j}else{if(!(f>=0&&f<q))return A.a(a5,f)
j=a5[f]
if(!(e>=0&&e<q))return A.a(a5,e)
A.dv(j,a5[e],r)
a=r[0]
j=r[1]
a5.$flags&2&&A.b(a5)
a5[e]=j}a5.$flags&2&&A.b(a5)
if(!(f>=0&&f<q))return A.a(a5,f)
a5[f]=a}}s=t>>>1}},
du(a,b,c){var t,s,r,q,p=$.am()
p.$flags&2&&A.b(p)
p[0]=a
t=$.au()
if(0>=t.length)return A.a(t,0)
s=t[0]
p[0]=b
r=t[0]
q=s+(r&1)+B.a.j(r,1)
B.c.i(c,0,q)
B.c.i(c,1,q-r)},
dv(a,b,c){var t=a-B.a.j(b,1)&65535
B.c.i(c,1,t)
B.c.i(c,0,b+t-32768&65535)},
q0(a){var t,s,r,q,p,o,n,m,l,k,j,i=null,h=new A.fy()
if(h.bm(a))return h
t=new A.fJ(A.li())
if(t.bm(a))return t
s=new A.hE()
s.f=A.v(a,!1,i,0)
s.a=new A.dy(A.j([],u.w))
if(s.eh())return s
r=new A.iE()
if(r.bm(a))return r
q=new A.ij()
if(q.ey(A.v(a,!1,i,0))!=null)return q
if(A.lC(a).c===943870035)return new A.i9()
if(A.n6(a))return new A.hy()
p=new A.eR(!1)
if(p.bm(a))return p
o=new A.i6(A.j([],u.s))
if(o.bm(a))return o
n=new A.ih()
m=A.v(a,!1,i,0)
l=n.a=new A.eq(B.ak)
l.bS(m)
if(l.f6())return n
k=new A.hI()
l=A.v(a,!1,i,0)
k.a=l
l=A.l6(l)
k.b=l
if(l!=null)return k
j=new A.id()
if(j.aP(a)!=null)return j
return i},
eN(a,b){return(a&65535)*b+((a>>>16)*b&65535)*65536>>>0},
ox(a,b,c,d,e,f){A.ou(f,a,b,c,d,e,!0,f)},
oy(a,b,c,d,e,f){A.ov(f,a,b,c,d,e,!0,f)},
ow(a,b,c,d,e,f){A.ot(f,a,b,c,d,e,!0,f)},
de(a,b,c,d,e){var t,s,r
for(t=0;t<d;++t){s=J.c(a.a,a.d+t)
r=J.c(b.a,b.d+t)
J.x(c.a,c.d+t,s+r)}},
ou(a,b,c,d,e,f,g,h){var t,s,r=null,q=e*d,p=e+f,o=A.v(a,!1,r,q),n=A.v(h,!1,r,q),m=A.o(n,r,0)
if(e===0){n.i(0,0,J.c(o.a,o.d))
A.de(A.o(o,r,1),m,A.o(n,r,1),b-1,!0)
m.d+=d
o.d+=d
n.d+=d
e=1}for(t=-d,s=b-1;e<p;){A.de(o,A.o(m,r,t),n,1,!0)
A.de(A.o(o,r,1),m,A.o(n,r,1),s,!0);++e
m.d+=d
o.d+=d
n.d+=d}},
ov(a,b,c,d,e,f,g,h){var t=null,s=e*d,r=e+f,q=A.v(a,!1,t,s),p=A.v(h,!1,t,s),o=A.o(p,t,0)
if(e===0){p.i(0,0,J.c(q.a,q.d))
A.de(A.o(q,t,1),o,A.o(p,t,1),b-1,!0)
q.d+=d
p.d+=d
e=1}else o.d-=d
while(e<r){A.de(q,o,p,b,!0);++e
o.d+=d
q.d+=d
p.d+=d}},
ot(a,b,c,d,e,f,g,h){var t,s,r,q,p,o=null,n=e*d,m=e+f,l=A.v(a,!1,o,n),k=A.v(h,!1,o,n),j=A.o(k,o,0)
if(e===0){k.i(0,0,J.c(l.a,l.d))
A.de(A.o(l,o,1),j,A.o(k,o,1),b-1,!0)
j.d+=d
l.d+=d
k.d+=d
e=1}for(t=-d;e<m;){A.de(l,A.o(j,o,t),k,1,!0)
for(s=1;s<b;++s){r=s-d
q=J.c(j.a,j.d+(s-1))+J.c(j.a,j.d+r)-J.c(j.a,j.d+(r-1))
if((q&4294967040)>>>0===0)p=q
else p=q<0?0:255
r=J.c(l.a,l.d+s)
J.x(k.a,k.d+s,r+p)}++e
j.d+=d
l.d+=d
k.d+=d}},
pS(a){var t="ifd0",s=A.bz(a,!1,!1)
if(!a.gbG().k(0,t).a.ae(274)||a.gbG().k(0,t).gc3()===1)return s
s.e=A.ds(a.gbG())
s.gbG().k(0,t).sc3(null)
switch(a.gbG().k(0,t).gc3()){case 2:return A.hm(s)
case 3:return A.q1(s,B.cP)
case 4:return A.hm(A.hl(s,180))
case 5:return A.hm(A.hl(s,90))
case 6:return A.hl(s,90)
case 7:return A.hm(A.hl(s,-90))
case 8:return A.hl(s,-90)}return s},
pX(e5,e6,e7,e8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,d0,d1,d2,d3,d4,d5,d6,d7,d8,d9,e0,e1,e2,e3,e4=null
if(e5.gcp())e7=B.as
if(e5.gbG().k(0,"ifd0").a.ae(274)&&e5.gbG().k(0,"ifd0").gc3()!==1)e5=A.pS(e5)
if(e6<=0)e6=B.b.aD(e8*(e5.gV()/e5.ga5()))
if(e8<=0)e8=B.b.aD(e6*(e5.ga5()/e5.gV()))
if(e8===e5.ga5()&&e6===e5.gV())return A.bz(e5,!1,!1)
t=new Int32Array(e8)
for(s=e5.a,r=s==null,q=0;q<e8;++q){p=r?e4:s.a
p=B.a.au(q*(p==null?0:p),e8)
if(!(q<e8))return A.a(t,q)
t[q]=p}o=new Int32Array(e6)
for(n=0;n<e6;++n){p=r?e4:s.b
p=B.a.au(n*(p==null?0:p),e6)
if(!(n<e6))return A.a(o,n)
o[n]=p}m=e5.gaA().length
for(s=e7===B.d7,r=e7===B.as,p=e7===B.b4,l=u.g,k=e4,j=0;j<m;++j){i=e5.x
if(i===$)i=e5.x=A.j([],l)
if(!(j<i.length))return A.a(i,j)
h=i[j]
g=A.fg(h,e6,!0,e8)
f=k==null
if(!f)k.aZ(g)
if(f)k=g
f=h.a
e=f==null
d=e?e4:f.b
c=(d==null?0:d)/e6
d=e?e4:f.a
b=(d==null?0:d)/e8
if(p){a=h.ab(0,0)
for(n=0;n<e6;n=a1){a0=B.b.h(n*c)
a1=n+1
a2=B.b.h(a1*c)
if(a2===a0)++a2
for(q=0;q<e8;q=a4){a3=B.b.h(q*b)
a4=q+1
a5=B.b.h(a4*b)
if(a5===a3)++a5
for(a6=a0,a7=0,a8=0,a9=0,b0=0,b1=0;a6<a2;++a6)for(b2=a3;b2<a5;++b2,++b1){f=h.a
if(f!=null)f.L(b2,a6,a)
a7+=a.gn()
a8+=a.gp()
a9+=a.gq()
b0+=a.gu()}b3=1/b1
f=g.a
if(f!=null)f.ak(q,n,a7*b3,a8*b3,a9*b3,b0*b3)}}}else if(r)if((e?e4:f.gR())!=null)for(n=0;n<e6;++n){if(!(n<e6))return A.a(o,n)
b4=o[n]
for(q=0;q<e8;++q){if(!(q<e8))return A.a(t,q)
f=t[q]
e=h.a
f=e==null?e4:B.b.h(e.aJ(f,b4).gN())
if(f==null)f=0
e=g.a
if(e!=null)e.aC(q,n,f)}}else{a=h.ab(0,0)
for(n=0;n<e6;++n){if(!(n<e6))return A.a(o,n)
a6=o[n]
for(q=0;q<e8;++q){if(!(q<e8))return A.a(t,q)
f=t[q]
e=h.a
if(e!=null)e.L(f,a6,a)
f=a.gn()
e=a.gp()
d=a.gq()
b5=a.gu()
b6=g.a
if(b6!=null)b6.ak(q,n,f,e,d,b5)}}}else if(s){b7=h.ab(0,0)
b8=h.ab(0,0)
b9=h.ab(0,0)
c0=h.ab(0,0)
f=h.a
e=f==null
d=e?e4:f.a
c1=(d==null?0:d)-1
f=e?e4:f.b
c2=(f==null?0:f)-1
for(n=0;n<e6;++n){c3=n*c
c4=B.b.h(c3)
c5=c3-c4
c6=B.a.J(c4+1,0,c2)
for(q=0;q<e8;++q){c7=q*b
c8=B.b.h(c7)
c9=c7-c8
d0=B.a.J(c8+1,0,c1)
f=h.a
if(f!=null)f.L(c8,c4,b7)
f=h.a
if(f!=null)f.L(c8,c6,b8)
f=h.a
if(f!=null)f.L(d0,c4,b9)
f=h.a
if(f!=null)f.L(d0,c6,c0)
f=b7.gn()
e=b9.gn()
d=b8.gn()
b5=c0.gn()
b6=b7.gp()
d1=b9.gp()
d2=b8.gp()
d3=c0.gp()
d4=b7.gq()
d5=b9.gq()
d6=b8.gq()
d7=c0.gq()
d8=b7.gu()
d9=b9.gu()
e0=b8.gu()
e1=c0.gu()
e2=g.a
if(e2!=null)e2.ak(q,n,f+c9*(e-f+c5*(f+b5-d-e))+c5*(d-f),b6+c9*(d1-b6+c5*(b6+d3-d2-d1))+c5*(d2-b6),d4+c9*(d5-d4+c5*(d4+d7-d6-d5))+c5*(d6-d4),d8+c9*(d9-d8+c5*(d8+e1-e0-d9))+c5*(e0-d8))}}}else for(n=0;n<e6;++n){e3=n*c
for(q=0;q<e8;++q)g.bI(q,n,h.dN(q*b,e3,e7))}}k.toString
return k},
hl(b0,b1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8=null,a9=B.a.a1(b1,360)
b0.gcp()
if(B.a.a1(a9,90)===0)switch(B.a.Y(a9,90)){case 1:return A.pG(b0)
case 2:return A.pE(b0)
case 3:return A.pF(b0)
default:return A.bz(b0,!1,!1)}t=a9*3.141592653589793/180
s=Math.cos(t)
r=Math.sin(t)
q=b0.ga5()
p=b0.ga5()
o=b0.gV()
n=b0.gV()
m=0.5*b0.ga5()
l=0.5*b0.gV()
o=Math.abs(q*s)+Math.abs(o*r)
k=0.5*o
n=Math.abs(p*r)+Math.abs(n*s)
j=0.5*n
i=b0.gaA().length
for(q=u.g,h=b0.f,g=a8,f=0;f<i;++f){e=b0.x
if(e===$)e=b0.x=A.j([],q)
if(!(f<e.length))return A.a(e,f)
d=e[f]
p=g==null
c=p?a8:g.d0()
if(c==null){b=B.b.h(o)
c=A.fg(b0,B.b.h(n),!0,b)}if(p)g=c
a=d.f
if(a==null)a=h
if(a!=null){p=c.a
if(p!=null)p.aK(0,a)}for(p=c.a,p=p.gI(p);p.F();){a0=p.gM()
a1=a0.gaL()
a2=a0.gaH()
b=a1-k
a3=a2-j
a4=m+b*s+a3*r
a5=l-b*r+a3*s
b=!1
if(a4>=0)if(a5>=0){a3=d.a
a6=a3==null
a7=a6?a8:a3.a
if(a4<(a7==null?0:a7)){b=a6?a8:a3.b
b=a5<(b==null?0:b)}}if(b)c.bI(a1,a2,d.dN(a4,a5,B.as))}}g.toString
return g},
pG(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=null
for(t=a.gaA(),s=t.length,r=g,q=0;q<t.length;t.length===s||(0,A.a_)(t),++q){p=t[q]
o=r==null
n=o?g:r.d0()
if(n==null){m=p.a
l=m==null
k=l?g:m.b
if(k==null)k=0
m=l?g:m.a
n=A.fg(p,m==null?0:m,!0,k)}if(o)r=n
o=p.a
o=o==null?g:o.b
j=(o==null?0:o)-1
i=0
for(;;){o=n.a
o=o==null?g:o.b
if(!(i<(o==null?0:o)))break
h=0
for(;;){o=n.a
o=o==null?g:o.a
if(!(h<(o==null?0:o)))break
o=p.a
o=o==null?g:o.L(i,j-h,g)
n.bI(h,i,o==null?new A.G():o);++h}++i}}r.toString
return r},
pE(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=null
for(t=a.gaA(),s=t.length,r=g,q=0;q<t.length;t.length===s||(0,A.a_)(t),++q){p=t[q]
o=p.a
n=o==null
m=n?g:o.a
l=(m==null?0:m)-1
o=n?g:o.b
k=(o==null?0:o)-1
o=r==null
j=o?g:r.d0()
if(j==null)j=A.bz(p,!0,!0)
if(o)r=j
i=0
for(;;){o=j.a
o=o==null?g:o.b
if(!(i<(o==null?0:o)))break
o=k-i
h=0
for(;;){n=j.a
n=n==null?g:n.a
if(!(h<(n==null?0:n)))break
n=p.a
n=n==null?g:n.L(l-h,o,g)
j.bI(h,i,n==null?new A.G():n);++h}++i}}r.toString
return r},
pF(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=null
for(t=a.gaA(),s=t.length,r=g,q=0;q<t.length;t.length===s||(0,A.a_)(t),++q){p=t[q]
o=a.a
o=o==null?g:o.a
n=(o==null?0:o)-1
o=r==null
m=o?g:r.d0()
if(m==null){l=p.a
k=l==null
j=k?g:l.b
if(j==null)j=0
l=k?g:l.a
m=A.fg(p,l==null?0:l,!0,j)}if(o)r=m
i=0
for(;;){o=m.a
o=o==null?g:o.b
if(!(i<(o==null?0:o)))break
o=n-i
h=0
for(;;){l=m.a
l=l==null?g:l.a
if(!(h<(l==null?0:l)))break
l=p.a
l=l==null?g:l.L(o,h,g)
m.bI(h,i,l==null?new A.G():l);++h}++i}}r.toString
return r},
jq(a){var t
a=(a&-a)>>>0
t=a!==0?31:32
if((a&65535)!==0)t-=16
if((a&16711935)!==0)t-=8
if((a&252645135)!==0)t-=4
if((a&858993459)!==0)t-=2
return(a&1431655765)!==0?t-1:t},
qp(a){var t
$.kL().i(0,0,a)
t=$.mH()
if(0>=t.length)return A.a(t,0)
return t[0]},
mm(a,b,c,d){return(B.a.J(a,0,255)|B.a.J(b,0,255)<<8|B.a.J(c,0,255)<<16|B.a.J(d,0,255)<<24)>>>0},
b1(a,b,c){var t,s,r,q,p=b.gt(b),o=b.gK(),n=a.gR(),m=n==null?null:n.gK()
if(m==null)m=a.gK()
t=a.gt(a)
if(p===1)b.i(0,0,A.hk(B.b.bQ(a.gt(a)>2?a.gaj():a.k(0,0)),m,o))
else if(p<=t)for(s=0;s<p;++s)b.i(0,s,A.hk(a.k(0,s),m,o))
else if(t===2){r=A.hk(a.k(0,0),m,o)
if(p===3){b.i(0,0,r)
b.i(0,1,r)
b.i(0,2,r)}else{c=A.hk(a.k(0,1),m,o)
b.i(0,0,r)
b.i(0,1,r)
b.i(0,2,r)
b.i(0,3,c)}}else{for(s=0;s<t;++s)b.i(0,s,A.hk(a.k(0,s),m,o))
q=t===1?b.k(0,0):0
for(s=t;s<p;++s)b.i(0,s,s===3?c:q)}return b},
az(a,b,c,d,e){var t,s,r=a.gR(),q=r==null?null:r.gK()
if(q==null)q=a.gK()
r=e==null
t=r?null:e.gK()
c=t==null?c:t
if(c==null)c=a.gK()
t=r?null:e.gt(e)
d=t==null?d:t
if(d==null)d=a.gt(a)
if(b==null)b=0
if(c===q&&d===a.gt(a)){if(r)return a.P()
e.ac(a)
return e}switch(c.a){case 3:if(r)s=new A.aS(new Uint8Array(d))
else s=e
return A.b1(a,s,b)
case 0:return A.b1(a,r?new A.cF(d,0):e,b)
case 1:return A.b1(a,r?new A.cH(d,0):e,b)
case 2:if(r){r=d<3?1:2
s=new A.cJ(d,new Uint8Array(r))}else s=e
return A.b1(a,s,b)
case 4:if(r)s=new A.cG(new Uint16Array(d))
else s=e
return A.b1(a,s,b)
case 5:if(r)s=new A.cI(new Uint32Array(d))
else s=e
return A.b1(a,s,b)
case 6:if(r)s=new A.cE(new Int8Array(d))
else s=e
return A.b1(a,s,b)
case 7:if(r)s=new A.cC(new Int16Array(d))
else s=e
return A.b1(a,s,b)
case 8:if(r)s=new A.cD(new Int32Array(d))
else s=e
return A.b1(a,s,b)
case 9:if(r)s=new A.cz(new Uint16Array(d))
else s=e
return A.b1(a,s,b)
case 10:if(r)s=new A.cA(new Float32Array(d))
else s=e
return A.b1(a,s,b)
case 11:if(r)s=new A.cB(new Float64Array(d))
else s=e
return A.b1(a,s,b)}},
X(a){return 0.299*a.gn()+0.587*a.gp()+0.114*a.gq()},
mf(a,b,c,d,e){var t=1-d/255
B.c.i(e,0,B.b.aD(255*(1-a/255)*t))
B.c.i(e,1,B.b.aD(255*(1-b/255)*t))
B.c.i(e,2,B.b.aD(255*(1-c/255)*t))},
I(a){var t,s,r,q=$.kK()
q.$flags&2&&A.b(q)
q[0]=a
q=$.mG()
if(0>=q.length)return A.a(q,0)
t=q[0]
if(a===0)return t>>>16
if($.N==null)A.U()
s=t>>>23&511
q=$.l2.ir()
if(!(s<q.length))return A.a(q,s)
s=q[s]
if(s!==0){r=t&8388607
return s+(r+4095+(r>>>13&1)>>>13)}return A.n8(t)},
n8(a){var t,s,r=a>>>16&32768,q=(a>>>23&255)-112,p=a&8388607
if(q<=0){if(q<-10)return r
p|=8388608
t=14-q
return(r|B.a.bs(p+(B.a.W(1,t-1)-1)+(B.a.a0(p,t)&1),t))>>>0}else if(q===143)if(p===0)return r|31744
else{p=p>>>13
s=p===0?1:0
return r|p|s|31744}else{p=p+4095+(p>>>13&1)
if((p&8388608)!==0){++q
p=0}if(q>30)return r|31744
return(r|q<<10|p>>>13)>>>0}},
U(){var t,s,r,q,p,o=$.N
if(o!=null)return o
t=new Uint32Array(65536)
$.N=J.kO(B.o.gB(t),0,null)
o=new Uint16Array(512)
$.l2.b=o
for(s=0;s<256;++s){r=(s&255)-112
if(r<=0||r>=30){o[s]=0
q=(s|256)>>>0
if(!(q<512))return A.a(o,q)
o[q]=0}else{q=r<<10>>>0
o[s]=q
p=(s|256)>>>0
if(!(p<512))return A.a(o,p)
o[p]=(q|32768)>>>0}}for(s=0;s<65536;++s)t[s]=A.n9(s)
o=$.N
o.toString
return o},
n9(a){var t,s=a>>>15&1,r=a>>>10&31,q=a&1023
if(r===0)if(q===0)return s<<31>>>0
else{while((q&1024)===0){q=q<<1;--r}++r
q&=4294966271}else if(r===31){t=s<<31
if(q===0)return(t|2139095040)>>>0
else return(t|q<<13|2139095040)>>>0}return(s<<31|r+112<<23|q<<13)>>>0}},B={}
var w=[A,J,B]
var $={}
A.k0.prototype={}
J.fk.prototype={
S(a,b){return a===b},
gH(a){return A.ei(a)},
D(a){return"Instance of '"+A.fL(a)+"'"},
gaE(a){return A.cu(A.kw(this))}}
J.fw.prototype={
D(a){return String(a)},
gH(a){return a?519018:218159},
gaE(a){return A.cu(u.y)},
$iM:1,
$ia3:1}
J.dN.prototype={
S(a,b){return null==b},
D(a){return"null"},
gH(a){return 0},
$iM:1}
J.dO.prototype={$iY:1}
J.bB.prototype={
gH(a){return 0},
D(a){return String(a)}}
J.fI.prototype={}
J.dc.prototype={}
J.bi.prototype={
D(a){var t=a[$.mo()]
if(t==null)t=a[$.kJ()]
if(t==null)return this.fC(a)
return"JavaScript function for "+J.ac(t)},
$ibW:1}
J.d_.prototype={
gH(a){return 0},
D(a){return String(a)}}
J.d0.prototype={
gH(a){return 0},
D(a){return String(a)}}
J.r.prototype={
A(a,b){A.al(a).c.a(b)
a.$flags&1&&A.b(a,29)
a.push(b)},
fd(a,b){var t
a.$flags&1&&A.b(a,"removeAt",1)
t=a.length
if(b>=t)throw A.f(A.lE(b,null))
return a.splice(b,1)[0]},
bD(a,b){A.al(a).v("e<1>").a(b)
a.$flags&1&&A.b(a,"addAll",2)
this.fZ(a,b)
return},
fZ(a,b){var t,s
u.b.a(b)
t=b.length
if(t===0)return
if(a===b)throw A.f(A.b2(a))
for(s=0;s<t;++s)a.push(b[s])},
dE(a){a.$flags&1&&A.b(a,"clear","clear")
a.length=0},
f8(a,b,c){var t=A.al(a)
return new A.c6(a,t.bJ(c).v("1(2)").a(b),t.v("@<1>").bJ(c).v("c6<1,2>"))},
c9(a,b){var t,s=A.P(a.length,"",!1,u.N)
for(t=0;t<a.length;++t)this.i(s,t,A.z(a[t]))
return s.join(b)},
fe(a,b){return A.ep(a,0,A.md(b,"count",u.p),A.al(a).c)},
da(a,b){return A.ep(a,b,null,A.al(a).c)},
bv(a,b){if(!(b>=0&&b<a.length))return A.a(a,b)
return a[b]},
b6(a,b,c){if(b<0||b>a.length)throw A.f(A.ak(b,0,a.length,"start",null))
if(c<b||c>a.length)throw A.f(A.ak(c,b,a.length,"end",null))
if(b===c)return A.j([],A.al(a))
return A.j(a.slice(b,c),A.al(a))},
gdI(a){if(a.length>0)return a[0]
throw A.f(A.jY())},
gf7(a){var t=a.length
if(t>0)return a[t-1]
throw A.f(A.jY())},
ar(a,b,c,d,e){var t,s,r,q,p
A.al(a).v("e<1>").a(d)
a.$flags&2&&A.b(a,5)
A.aZ(b,c,a.length)
t=c-b
if(t===0)return
A.d8(e,"skipCount")
if(u.j.b(d)){s=d
r=e}else{s=J.jM(d,e).ff(0,!1)
r=0}q=J.S(s)
if(r+t>q.gt(s))throw A.f(A.lj())
if(r<b)for(p=t-1;p>=0;--p)a[b+p]=q.k(s,r+p)
else for(p=0;p<t;++p)a[b+p]=q.k(s,r+p)},
aB(a,b,c,d){var t
A.al(a).v("1?").a(d)
a.$flags&2&&A.b(a,"fillRange")
A.aZ(b,c,a.length)
for(t=b;t<c;++t)a[t]=d},
eN(a,b){var t,s
A.al(a).v("a3(1)").a(b)
t=a.length
for(s=0;s<t;++s){if(b.$1(a[s]))return!0
if(a.length!==t)throw A.f(A.b2(a))}return!1},
fz(a){var t,s,r,q,p,o
a.$flags&2&&A.b(a,"sort")
t=a.length
if(t<2)return
if(t===2){s=a[0]
r=a[1]
q=J.lm(s,r)
if(typeof q!=="number")return q.fo()
if(q>0){a[0]=r
a[1]=s}return}p=0
if(A.al(a).c.b(null))for(o=0;o<a.length;++o)if(a[o]===void 0){a[o]=null;++p}a.sort(A.pU(J.pg(),2))
if(p>0)this.iK(a,p)},
iK(a,b){var t,s=a.length
for(;t=s-1,s>0;s=t)if(a[t]===null){a[t]=void 0;--b
if(b===0)break}},
jf(a,b){var t,s=a.length
if(0>=s)return-1
for(t=0;t<s;++t){if(!(t<a.length))return A.a(a,t)
if(J.bO(a[t],b))return t}return-1},
aR(a,b){var t
for(t=0;t<a.length;++t)if(J.bO(a[t],b))return!0
return!1},
gaU(a){return a.length===0},
gdK(a){return a.length!==0},
D(a){return A.jZ(a,"[","]")},
gI(a){return new J.bR(a,a.length,A.al(a).v("bR<1>"))},
gH(a){return A.ei(a)},
gt(a){return a.length},
st(a,b){a.$flags&1&&A.b(a,"set length","change the length of")
if(b<0)throw A.f(A.ak(b,0,null,"newLength",null))
if(b>a.length)A.al(a).c.a(null)
a.length=b},
k(a,b){if(!(b>=0&&b<a.length))throw A.f(A.jr(a,b))
return a[b]},
i(a,b,c){A.al(a).c.a(c)
a.$flags&2&&A.b(a)
if(!(b>=0&&b<a.length))throw A.f(A.jr(a,b))
a[b]=c},
$iah:1,
$ie:1,
$ip:1}
J.fv.prototype={
jB(a){var t,s,r
if(!Array.isArray(a))return null
t=a.$flags|0
if((t&4)!==0)s="const, "
else if((t&2)!==0)s="unmodifiable, "
else s=(t&1)!==0?"fixed, ":""
r="Instance of '"+A.fL(a)+"'"
if(s==="")return r
return r+" ("+s+"length: "+a.length+")"}}
J.hR.prototype={}
J.bR.prototype={
gM(){var t=this.d
return t==null?this.$ti.c.a(t):t},
F(){var t,s=this,r=s.a,q=r.length
if(s.b!==q){r=A.a_(r)
throw A.f(r)}t=s.c
if(t>=q){s.d=null
return!1}s.d=r[t]
s.c=t+1
return!0},
$iA:1}
J.cZ.prototype={
cl(a,b){var t
A.bK(b)
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){t=this.gd5(b)
if(this.gd5(a)===t)return 0
if(this.gd5(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gd5(a){return a===0?1/a<0:a<0},
h(a){var t
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){t=a<0?Math.ceil(a):Math.floor(a)
return t+0}throw A.f(A.b5(""+a+".toInt()"))},
b0(a){var t,s
if(a>=0){if(a<=2147483647){t=a|0
return a===t?t:t+1}}else if(a>=-2147483648)return a|0
s=Math.ceil(a)
if(isFinite(s))return s
throw A.f(A.b5(""+a+".ceil()"))},
bQ(a){var t,s
if(a>=0){if(a<=2147483647)return a|0}else if(a>=-2147483648){t=a|0
return a===t?t:t-1}s=Math.floor(a)
if(isFinite(s))return s
throw A.f(A.b5(""+a+".floor()"))},
aD(a){if(a>0){if(a!==1/0)return Math.round(a)}else if(a>-1/0)return 0-Math.round(0-a)
throw A.f(A.b5(""+a+".round()"))},
J(a,b,c){if(this.cl(b,c)>0)throw A.f(A.bM(b))
if(this.cl(a,b)<0)return b
if(this.cl(a,c)>0)return c
return a},
bn(a,b){var t
if(b>20)throw A.f(A.ak(b,0,20,"fractionDigits",null))
t=a.toFixed(b)
if(a===0&&this.gd5(a))return"-"+t
return t},
d7(a,b){var t,s,r,q,p
if(b<2||b>36)throw A.f(A.ak(b,2,36,"radix",null))
t=a.toString(b)
s=t.length
r=s-1
if(!(r>=0))return A.a(t,r)
if(t.charCodeAt(r)!==41)return t
q=/^([\da-z]+)(?:\.([\da-z]+))?\(e\+(\d+)\)$/.exec(t)
if(q==null)A.aA(A.b5("Unexpected toString result: "+t))
s=q.length
if(1>=s)return A.a(q,1)
t=q[1]
if(3>=s)return A.a(q,3)
p=+q[3]
s=q[2]
if(s!=null){t+=s
p-=s.length}return t+B.p.dO("0",p)},
D(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gH(a){var t,s,r,q,p=a|0
if(a===p)return p&536870911
t=Math.abs(a)
s=Math.log(t)/0.6931471805599453|0
r=Math.pow(2,s)
q=t<1?t/r:r/t
return((q*9007199254740992|0)+(q*3542243181176521|0))*599197+s*1259&536870911},
a1(a,b){var t=a%b
if(t===0)return 0
if(t>0)return t
if(b<0)return t-b
else return t+b},
au(a,b){A.bK(b)
if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.eE(a,b)},
Y(a,b){return(a|0)===a?a/b|0:this.eE(a,b)},
eE(a,b){var t=a/b
if(t>=-2147483648&&t<=2147483647)return t|0
if(t>0){if(t!==1/0)return Math.floor(t)}else if(t>-1/0)return Math.ceil(t)
throw A.f(A.b5("Result of truncating division is "+A.z(t)+": "+A.z(a)+" ~/ "+b))},
W(a,b){if(b<0)throw A.f(A.bM(b))
return b>31?0:a<<b>>>0},
O(a,b){return b>31?0:a<<b>>>0},
bs(a,b){var t
if(b<0)throw A.f(A.bM(b))
if(a>0)t=this.a_(a,b)
else{t=b>31?31:b
t=a>>t>>>0}return t},
j(a,b){var t
if(a>0)t=this.a_(a,b)
else{t=b>31?31:b
t=a>>t>>>0}return t},
a0(a,b){if(0>b)throw A.f(A.bM(b))
return this.a_(a,b)},
a_(a,b){return b>31?0:a>>>b},
gaE(a){return A.cu(u.q)},
$ibd:1,
$iB:1,
$ik:1}
J.dM.prototype={
aq(a,b){var t=this.W(1,b-1)
return((a&t-1)>>>0)-((a&t)>>>0)},
gaE(a){return A.cu(u.p)},
$iM:1,
$ih:1}
J.fx.prototype={
gaE(a){return A.cu(u.i)},
$iM:1}
J.c5.prototype={
dR(a,b){var t=b.length
if(t>a.length)return!1
return b===a.substring(0,t)},
cI(a,b,c){return a.substring(b,A.aZ(b,c,a.length))},
fi(a){var t,s,r,q=a.trim(),p=q.length
if(p===0)return q
if(0>=p)return A.a(q,0)
if(q.charCodeAt(0)===133){t=J.nk(q,1)
if(t===p)return""}else t=0
s=p-1
if(!(s>=0))return A.a(q,s)
r=q.charCodeAt(s)===133?J.nl(q,s):p
if(t===0&&r===p)return q
return q.substring(t,r)},
dO(a,b){var t,s
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.f(B.cz)
for(t=a,s="";;){if((b&1)===1)s=t+s
b=b>>>1
if(b===0)break
t+=t}return s},
aR(a,b){return A.qk(a,b,0)},
cl(a,b){var t
A.b0(b)
if(a===b)t=0
else t=a<b?-1:1
return t},
D(a){return a},
gH(a){var t,s,r
for(t=a.length,s=0,r=0;r<t;++r){s=s+a.charCodeAt(r)&536870911
s=s+((s&524287)<<10)&536870911
s^=s>>6}s=s+((s&67108863)<<3)&536870911
s^=s>>11
return s+((s&16383)<<15)&536870911},
gaE(a){return A.cu(u.N)},
gt(a){return a.length},
$iah:1,
$iM:1,
$ibd:1,
$ily:1,
$iC:1}
A.iI.prototype={
A(a,b){var t,s,r=this
u.L.a(b)
t=b.length
if(t===0)return
s=r.a+t
if(r.b.length<s)r.em(s)
B.e.bk(r.b,r.a,s,b)
r.a=s},
eM(a){var t=this,s=t.b,r=t.a
if(s.length===r)t.em(r)
s=t.b
r=t.a
s.$flags&2&&A.b(s)
if(!(r<s.length))return A.a(s,r)
s[r]=a
t.a=r+1},
em(a){var t,s,r,q=a*2
if(q<1024)q=1024
else{t=q-1
t|=B.a.j(t,1)
t|=t>>>2
t|=t>>>4
t|=t>>>8
q=((t|t>>>16)>>>0)+1}s=new Uint8Array(q)
r=this.b
B.e.bk(s,0,r.length,r)
this.b=s},
jx(){var t,s=this
if(s.a===0)return $.jJ()
t=J.V(B.e.gB(s.b),s.b.byteOffset,s.a)
s.a=0
s.b=$.jJ()
return t},
gt(a){return this.a}}
A.d1.prototype={
D(a){return"LateInitializationError: "+this.a}}
A.aJ.prototype={
gt(a){return this.a.length},
k(a,b){var t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t.charCodeAt(b)}}
A.ie.prototype={}
A.dp.prototype={}
A.a1.prototype={
gI(a){var t=this
return new A.bk(t,t.gt(t),A.l(t).v("bk<a1.E>"))},
gaU(a){return this.gt(this)===0}}
A.eo.prototype={
ghF(){var t=J.ao(this.a),s=this.c
if(s==null||s>t)return t
return s},
giN(){var t=J.ao(this.a),s=this.b
if(s>t)return t
return s},
gt(a){var t,s=J.ao(this.a),r=this.b
if(r>=s)return 0
t=this.c
if(t==null||t>=s)return s-r
return t-r},
bv(a,b){var t=this,s=t.giN()+b
if(b<0||s>=t.ghF())throw A.f(A.jV(b,t.gt(0),t,"index"))
return J.kQ(t.a,s)},
da(a,b){var t,s,r=this
A.d8(b,"count")
t=r.b+b
s=r.c
if(s!=null&&t>=s)return new A.dq(r.$ti.v("dq<1>"))
return A.ep(r.a,t,s,r.$ti.c)},
ff(a,b){var t,s,r,q=this,p=q.b,o=q.a,n=J.S(o),m=n.gt(o),l=q.c
if(l!=null&&l<m)m=l
t=m-p
if(t<=0){o=J.lk(0,q.$ti.c)
return o}s=A.P(t,n.bv(o,p),!1,q.$ti.c)
for(r=1;r<t;++r){B.c.i(s,r,n.bv(o,p+r))
if(n.gt(o)<m)throw A.f(A.b2(q))}return s}}
A.bk.prototype={
gM(){var t=this.d
return t==null?this.$ti.c.a(t):t},
F(){var t,s=this,r=s.a,q=J.S(r),p=q.gt(r)
if(s.b!==p)throw A.f(A.b2(r))
t=s.c
if(t>=p){s.d=null
return!1}s.d=q.bv(r,t);++s.c
return!0},
$iA:1}
A.c6.prototype={
gt(a){return J.ao(this.a)},
bv(a,b){return this.b.$1(J.kQ(this.a,b))}}
A.bs.prototype={
gI(a){return new A.eA(J.bu(this.a),this.b,this.$ti.v("eA<1>"))}}
A.eA.prototype={
F(){var t,s
for(t=this.a,s=this.b;t.F();)if(s.$1(t.gM()))return!0
return!1},
gM(){return this.a.gM()},
$iA:1}
A.dq.prototype={
gI(a){return B.cs},
gt(a){return 0}}
A.dr.prototype={
F(){return!1},
gM(){throw A.f(A.jY())},
$iA:1}
A.ax.prototype={}
A.bp.prototype={
i(a,b,c){A.l(this).v("bp.E").a(c)
throw A.f(A.b5("Cannot modify an unmodifiable list"))},
ar(a,b,c,d,e){A.l(this).v("e<bp.E>").a(d)
throw A.f(A.b5("Cannot modify an unmodifiable list"))},
bk(a,b,c,d){return this.ar(0,b,c,d,0)},
aB(a,b,c,d){A.l(this).v("bp.E?").a(d)
throw A.f(A.b5("Cannot modify an unmodifiable list"))}}
A.dd.prototype={}
A.cK.prototype={
gaU(a){return this.gt(this)===0},
D(a){return A.k3(this)},
$ia8:1}
A.dn.prototype={
gt(a){return this.b.length},
gep(){var t=this.$keys
if(t==null){t=Object.keys(this.a)
this.$keys=t}return t},
ae(a){if(typeof a!="string")return!1
if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
k(a,b){if(!this.ae(b))return null
return this.b[this.a[b]]},
aT(a,b){var t,s,r,q
this.$ti.v("~(1,2)").a(b)
t=this.gep()
s=this.b
for(r=t.length,q=0;q<r;++q)b.$2(t[q],s[q])},
gbw(){return new A.eB(this.gep(),this.$ti.v("eB<1>"))}}
A.eB.prototype={
gt(a){return this.a.length},
gI(a){var t=this.a
return new A.cq(t,t.length,this.$ti.v("cq<1>"))}}
A.cq.prototype={
gM(){var t=this.d
return t==null?this.$ti.c.a(t):t},
F(){var t=this,s=t.c
if(s>=t.b){t.d=null
return!1}t.d=t.a[s]
t.c=s+1
return!0},
$iA:1}
A.bX.prototype={
cT(){var t=this,s=t.$map
if(s==null){s=new A.dP(t.$ti.v("dP<1,2>"))
A.mg(t.a,s)
t.$map=s}return s},
k(a,b){return this.cT().k(0,b)},
aT(a,b){this.$ti.v("~(1,2)").a(b)
this.cT().aT(0,b)},
gbw(){var t=this.cT()
return new A.bj(t,A.l(t).v("bj<1>"))},
gt(a){return this.cT().a}}
A.dm.prototype={
A(a,b){A.l(this).c.a(b)
A.n0()}}
A.bU.prototype={
gt(a){return this.b},
gI(a){var t,s=this,r=s.$keys
if(r==null){r=Object.keys(s.a)
s.$keys=r}t=r
return new A.cq(t,t.length,s.$ti.v("cq<1>"))},
aR(a,b){if(typeof b!="string")return!1
if("__proto__"===b)return!1
return this.a.hasOwnProperty(b)}}
A.el.prototype={}
A.il.prototype={
bx(a){var t,s,r=this,q=new RegExp(r.a).exec(a)
if(q==null)return null
t=Object.create(null)
s=r.b
if(s!==-1)t.arguments=q[s+1]
s=r.c
if(s!==-1)t.argumentsExpr=q[s+1]
s=r.d
if(s!==-1)t.expr=q[s+1]
s=r.e
if(s!==-1)t.method=q[s+1]
s=r.f
if(s!==-1)t.receiver=q[s+1]
return t}}
A.e2.prototype={
D(a){return"Null check operator used on a null value"}}
A.fB.prototype={
D(a){var t,s=this,r="NoSuchMethodError: method not found: '",q=s.b
if(q==null)return"NoSuchMethodError: "+s.a
t=s.c
if(t==null)return r+q+"' ("+s.a+")"
return r+q+"' on '"+t+"' ("+s.a+")"}}
A.h4.prototype={
D(a){var t=this.a
return t.length===0?"Error":"Error: "+t}}
A.i3.prototype={
D(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bv.prototype={
D(a){var t=this.constructor,s=t==null?null:t.name
return"Closure '"+A.mn(s==null?"unknown":s)+"'"},
$ibW:1,
gjK(){return this},
$C:"$1",
$R:1,
$D:null}
A.eT.prototype={$C:"$0",$R:0}
A.eU.prototype={$C:"$2",$R:2}
A.h_.prototype={}
A.fY.prototype={
D(a){var t=this.$static_name
if(t==null)return"Closure of unknown static method"
return"Closure '"+A.mn(t)+"'"}}
A.cy.prototype={
S(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.cy))return!1
return this.$_target===b.$_target&&this.a===b.a},
gH(a){return(A.kE(this.a)^A.ei(this.$_target))>>>0},
D(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.fL(this.a)+"'")}}
A.fX.prototype={
D(a){return"RuntimeError: "+this.a}}
A.aV.prototype={
gt(a){return this.a},
gaU(a){return this.a===0},
gbw(){return new A.bj(this,A.l(this).v("bj<1>"))},
ae(a){var t,s
if(typeof a=="string"){t=this.b
if(t==null)return!1
return t[a]!=null}else if(typeof a=="number"&&(a&0x3fffffff)===a){s=this.c
if(s==null)return!1
return s[a]!=null}else return this.jg(a)},
jg(a){var t=this.d
if(t==null)return!1
return this.cs(t[this.cr(a)],a)>=0},
k(a,b){var t,s,r,q,p=null
if(typeof b=="string"){t=this.b
if(t==null)return p
s=t[b]
r=s==null?p:s.b
return r}else if(typeof b=="number"&&(b&0x3fffffff)===b){q=this.c
if(q==null)return p
s=q[b]
r=s==null?p:s.b
return r}else return this.jh(b)},
jh(a){var t,s,r=this.d
if(r==null)return null
t=r[this.cr(a)]
s=this.cs(t,a)
if(s<0)return null
return t[s].b},
i(a,b,c){var t,s,r=this,q=A.l(r)
q.c.a(b)
q.y[1].a(c)
if(typeof b=="string"){t=r.b
r.dW(t==null?r.b=r.ds():t,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){s=r.c
r.dW(s==null?r.c=r.ds():s,b,c)}else r.jj(b,c)},
jj(a,b){var t,s,r,q,p=this,o=A.l(p)
o.c.a(a)
o.y[1].a(b)
t=p.d
if(t==null)t=p.d=p.ds()
s=p.cr(a)
r=t[s]
if(r==null)t[s]=[p.dd(a,b)]
else{q=p.cs(r,a)
if(q>=0)r[q].b=b
else r.push(p.dd(a,b))}},
fa(a,b){var t,s,r=this,q=A.l(r)
q.c.a(a)
q.v("2()").a(b)
if(r.ae(a)){t=r.k(0,a)
return t==null?q.y[1].a(t):t}s=b.$0()
r.i(0,a,s)
return s},
bT(a,b){var t=this
if(typeof b=="string")return t.eB(t.b,b)
else if(typeof b=="number"&&(b&0x3fffffff)===b)return t.eB(t.c,b)
else return t.ji(b)},
ji(a){var t,s,r,q,p=this,o=p.d
if(o==null)return null
t=p.cr(a)
s=o[t]
r=p.cs(s,a)
if(r<0)return null
q=s.splice(r,1)[0]
p.eG(q)
if(s.length===0)delete o[t]
return q.b},
aT(a,b){var t,s,r=this
A.l(r).v("~(1,2)").a(b)
t=r.e
s=r.r
while(t!=null){b.$2(t.a,t.b)
if(s!==r.r)throw A.f(A.b2(r))
t=t.c}},
dW(a,b,c){var t,s=A.l(this)
s.c.a(b)
s.y[1].a(c)
t=a[b]
if(t==null)a[b]=this.dd(b,c)
else t.b=c},
eB(a,b){var t
if(a==null)return null
t=a[b]
if(t==null)return null
this.eG(t)
delete a[b]
return t.b},
eq(){this.r=this.r+1&1073741823},
dd(a,b){var t=this,s=A.l(t),r=new A.i_(s.c.a(a),s.y[1].a(b))
if(t.e==null)t.e=t.f=r
else{s=t.f
s.toString
r.d=s
t.f=s.c=r}++t.a
t.eq()
return r},
eG(a){var t=this,s=a.d,r=a.c
if(s==null)t.e=r
else s.c=r
if(r==null)t.f=s
else r.d=s;--t.a
t.eq()},
cr(a){return J.bP(a)&1073741823},
cs(a,b){var t,s
if(a==null)return-1
t=a.length
for(s=0;s<t;++s)if(J.bO(a[s].a,b))return s
return-1},
D(a){return A.k3(this)},
ds(){var t=Object.create(null)
t["<non-identifier-key>"]=t
delete t["<non-identifier-key>"]
return t},
$ik2:1}
A.i_.prototype={}
A.bj.prototype={
gt(a){return this.a.a},
gaU(a){return this.a.a===0},
gI(a){var t=this.a
return new A.O(t,t.r,t.e,this.$ti.v("O<1>"))}}
A.O.prototype={
gM(){return this.d},
F(){var t,s=this,r=s.a
if(s.b!==r.r)throw A.f(A.b2(r))
t=s.c
if(t==null){s.d=null
return!1}else{s.d=t.a
s.c=t.c
return!0}},
$iA:1}
A.dR.prototype={
gt(a){return this.a.a},
gI(a){var t=this.a
return new A.aq(t,t.r,t.e,this.$ti.v("aq<1>"))}}
A.aq.prototype={
gM(){return this.d},
F(){var t,s=this,r=s.a
if(s.b!==r.r)throw A.f(A.b2(r))
t=s.c
if(t==null){s.d=null
return!1}else{s.d=t.b
s.c=t.c
return!0}},
$iA:1}
A.dP.prototype={
cr(a){return A.pT(a)&1073741823},
cs(a,b){var t,s
if(a==null)return-1
t=a.length
for(s=0;s<t;++s)if(J.bO(a[s].a,b))return s
return-1}}
A.jB.prototype={
$1(a){return this.a(a)},
$S:9}
A.jC.prototype={
$2(a,b){return this.a(a,b)},
$S:23}
A.jD.prototype={
$1(a){return this.a(A.b0(a))},
$S:20}
A.fZ.prototype={$ilv:1}
A.iR.prototype={
F(){var t,s,r=this,q=r.c,p=r.b,o=p.length,n=r.a,m=n.length
if(q+o>m){r.d=null
return!1}t=n.indexOf(p,q)
if(t<0){r.c=m+1
r.d=null
return!1}s=t+o
r.d=new A.fZ(t,p)
r.c=s===r.c?s+1:s
return!0},
gM(){var t=this.d
t.toString
return t},
$iA:1}
A.iH.prototype={
ir(){var t=this.b
if(t===this)throw A.f(A.lq(""))
return t}}
A.c7.prototype={
gaE(a){return B.kB},
d2(a,b,c){A.at(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
eV(a){return this.d2(a,0,null)},
eS(a,b,c){A.at(a,b,c)
return c==null?new Int8Array(a,b):new Int8Array(a,b,c)},
d1(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,2)
return new Uint16Array(a,b,c)},
eT(a){return this.d1(a,0,null)},
eQ(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,2)
return new Int16Array(a,b,c)},
eU(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Uint32Array(a,b,c)},
eR(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Int32Array(a,b,c)},
eP(a,b,c){A.at(a,b,c)
c=B.a.Y(a.byteLength-b,4)
return new Float32Array(a,b,c)},
eO(a,b,c){var t
A.at(a,b,c)
t=new DataView(a,b,c)
return t},
$iM:1,
$ic7:1}
A.dY.prototype={
gB(a){if(((a.$flags|0)&2)!==0)return new A.iV(a.buffer)
else return a.buffer},
hX(a,b,c,d){var t=A.ak(b,0,c,d,null)
throw A.f(t)},
e3(a,b,c,d){if(b>>>0!==b||b>c)this.hX(a,b,c,d)},
$ia2:1}
A.iV.prototype={
d2(a,b,c){var t=A.nA(this.a,b,c)
t.$flags=3
return t},
eV(a){return this.d2(0,0,null)},
eS(a,b,c){var t=A.nv(this.a,b,c)
t.$flags=3
return t},
d1(a,b,c){var t=A.nx(this.a,b,c)
t.$flags=3
return t},
eT(a){return this.d1(0,0,null)},
eQ(a,b,c){var t=A.ns(this.a,b,c)
t.$flags=3
return t},
eU(a,b,c){var t=A.nz(this.a,b,c)
t.$flags=3
return t},
eR(a,b,c){var t=A.nu(this.a,b,c)
t.$flags=3
return t},
eP(a,b,c){var t=A.nr(this.a,b,c)
t.$flags=3
return t},
eO(a,b,c){var t=A.np(this.a,b,c)
t.$flags=3
return t}}
A.dS.prototype={
gaE(a){return B.kC},
$iM:1}
A.aj.prototype={
gt(a){return a.length},
eC(a,b,c,d,e){var t,s,r=a.length
this.e3(a,b,r,"start")
this.e3(a,c,r,"end")
if(b>c)throw A.f(A.ak(b,0,c,null,null))
t=c-b
if(e<0)throw A.f(A.bQ(e))
s=d.length
if(s-e<t)throw A.f(A.nK("Not enough elements"))
if(e!==0||s!==t)d=d.subarray(e,e+t)
a.set(d,b)},
$iah:1,
$iaL:1}
A.bC.prototype={
k(a,b){A.bL(b,a,a.length)
return a[b]},
i(a,b,c){A.m0(c)
a.$flags&2&&A.b(a)
A.bL(b,a,a.length)
a[b]=c},
ar(a,b,c,d,e){u.bM.a(d)
a.$flags&2&&A.b(a,5)
if(u.d4.b(d)){this.eC(a,b,c,d,e)
return}this.dT(a,b,c,d,e)},
bk(a,b,c,d){return this.ar(a,b,c,d,0)},
$ie:1,
$ip:1}
A.aM.prototype={
i(a,b,c){A.u(c)
a.$flags&2&&A.b(a)
A.bL(b,a,a.length)
a[b]=c},
ar(a,b,c,d,e){u.hb.a(d)
a.$flags&2&&A.b(a,5)
if(u.bc.b(d)){this.eC(a,b,c,d,e)
return}this.dT(a,b,c,d,e)},
bk(a,b,c,d){return this.ar(a,b,c,d,0)},
$ie:1,
$ip:1}
A.dT.prototype={
gaE(a){return B.kD},
b6(a,b,c){return new Float32Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ihB:1}
A.dU.prototype={
gaE(a){return B.kE},
b6(a,b,c){return new Float64Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ijS:1}
A.dV.prototype={
gaE(a){return B.kF},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Int16Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ihQ:1}
A.dW.prototype={
gaE(a){return B.kG},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Int32Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$idH:1}
A.dX.prototype={
gaE(a){return B.kH},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Int8Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ijX:1}
A.dZ.prototype={
gaE(a){return B.kJ},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Uint16Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ikn:1}
A.e_.prototype={
gaE(a){return B.kK},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Uint32Array(a.subarray(b,A.b6(b,c,a.length)))},
$iM:1,
$ibo:1}
A.c8.prototype={
gaE(a){return B.kL},
gt(a){return a.length},
k(a,b){A.bL(b,a,a.length)
return a[b]},
b6(a,b,c){return new Uint8Array(a.subarray(b,A.b6(b,c,a.length)))},
fA(a,b){return this.b6(a,b,null)},
$iM:1,
$ic8:1,
$iaE:1}
A.eD.prototype={}
A.eE.prototype={}
A.eF.prototype={}
A.eG.prototype={}
A.b_.prototype={
v(a){return A.iU(v.typeUniverse,this,a)},
bJ(a){return A.oP(v.typeUniverse,this,a)}}
A.hd.prototype={}
A.hh.prototype={
D(a){return A.aG(this.a,null)}}
A.hb.prototype={
D(a){return this.a}}
A.eJ.prototype={}
A.cr.prototype={
gI(a){var t=this,s=new A.eC(t,t.r,A.l(t).v("eC<1>"))
s.c=t.e
return s},
gt(a){return this.a},
A(a,b){var t,s,r=this
A.l(r).c.a(b)
if(typeof b=="string"&&b!=="__proto__"){t=r.b
return r.dX(t==null?r.b=A.kr():t,b)}else if(typeof b=="number"&&(b&1073741823)===b){s=r.c
return r.dX(s==null?r.c=A.kr():s,b)}else return r.fY(b)},
fY(a){var t,s,r,q=this
A.l(q).c.a(a)
t=q.d
if(t==null)t=q.d=A.kr()
s=q.h7(a)
r=t[s]
if(r==null)t[s]=[q.dt(a)]
else{if(q.hM(r,a)>=0)return!1
r.push(q.dt(a))}return!0},
dX(a,b){A.l(this).c.a(b)
if(u.br.a(a[b])!=null)return!1
a[b]=this.dt(b)
return!0},
dt(a){var t=this,s=new A.hg(A.l(t).c.a(a))
if(t.e==null)t.e=t.f=s
else t.f=t.f.b=s;++t.a
t.r=t.r+1&1073741823
return s},
h7(a){return J.bP(a)&1073741823},
hM(a,b){var t,s
if(a==null)return-1
t=a.length
for(s=0;s<t;++s)if(J.bO(a[s].a,b))return s
return-1}}
A.hg.prototype={}
A.eC.prototype={
gM(){var t=this.d
return t==null?this.$ti.c.a(t):t},
F(){var t=this,s=t.c,r=t.a
if(t.b!==r.r)throw A.f(A.b2(r))
else if(s==null){t.d=null
return!1}else{t.d=t.$ti.v("1?").a(s.a)
t.c=s.b
return!0}},
$iA:1}
A.i0.prototype={
$2(a,b){this.a.i(0,this.b.a(a),this.c.a(b))},
$S:6}
A.F.prototype={
gI(a){return new A.bk(a,this.gt(a),A.aR(a).v("bk<F.E>"))},
bv(a,b){return this.k(a,b)},
gaU(a){return this.gt(a)===0},
gdK(a){return this.gt(a)!==0},
aR(a,b){var t,s=this.gt(a)
for(t=0;t<s;++t){if(this.k(a,t)===b)return!0
if(s!==this.gt(a))throw A.f(A.b2(a))}return!1},
f8(a,b,c){var t=A.aR(a)
return new A.c6(a,t.bJ(c).v("1(F.E)").a(b),t.v("@<F.E>").bJ(c).v("c6<1,2>"))},
da(a,b){return A.ep(a,b,null,A.aR(a).v("F.E"))},
fe(a,b){return A.ep(a,0,A.md(b,"count",u.p),A.aR(a).v("F.E"))},
b6(a,b,c){var t,s=this.gt(a)
A.aZ(b,c,s)
A.aZ(b,c,this.gt(a))
t=A.aR(a).v("F.E")
t=A.q(A.ep(a,b,c,t),t)
return t},
aB(a,b,c,d){var t
A.aR(a).v("F.E?").a(d)
A.aZ(b,c,this.gt(a))
for(t=b;t<c;++t)this.i(a,t,d)},
ar(a,b,c,d,e){var t,s,r,q,p
A.aR(a).v("e<F.E>").a(d)
A.aZ(b,c,this.gt(a))
t=c-b
if(t===0)return
A.d8(e,"skipCount")
if(u.j.b(d)){s=e
r=d}else{r=J.jM(d,e).ff(0,!1)
s=0}q=J.S(r)
if(s+t>q.gt(r))throw A.f(A.lj())
if(s<b)for(p=t-1;p>=0;--p)this.i(a,b+p,q.k(r,s+p))
else for(p=0;p<t;++p)this.i(a,b+p,q.k(r,s+p))},
bk(a,b,c,d){return this.ar(a,b,c,d,0)},
d9(a,b,c){A.aR(a).v("e<F.E>").a(c)
this.bk(a,b,b+c.length,c)},
D(a){return A.jZ(a,"[","]")},
$ie:1,
$ip:1}
A.ai.prototype={
aT(a,b){var t,s,r,q=A.l(this)
q.v("~(ai.K,ai.V)").a(b)
for(t=this.gbw(),t=t.gI(t),q=q.v("ai.V");t.F();){s=t.gM()
r=this.k(0,s)
b.$2(s,r==null?q.a(r):r)}},
gt(a){var t=this.gbw()
return t.gt(t)},
gaU(a){var t=this.gbw()
return t.gaU(t)},
D(a){return A.k3(this)},
$ia8:1}
A.i2.prototype={
$2(a,b){var t,s=this.a
if(!s.a)this.b.a+=", "
s.a=!1
s=this.b
t=A.z(a)
s.a=(s.a+=t)+": "
t=A.z(b)
s.a+=t},
$S:10}
A.bG.prototype={
bD(a,b){var t,s,r
A.l(this).v("e<1>").a(b)
for(t=b.$ti,s=new A.bk(b,b.gt(0),t.v("bk<a1.E>")),t=t.v("a1.E");s.F();){r=s.d
this.A(0,r==null?t.a(r):r)}},
D(a){return A.jZ(this,"{","}")},
c9(a,b){var t,s,r=this.gI(this)
if(!r.F())return""
t=J.ac(r.gM())
if(!r.F())return t
if(b.length===0){s=t
do s+=A.z(r.gM())
while(r.F())}else{s=t
do s=s+b+A.z(r.gM())
while(r.F())}return s.charCodeAt(0)==0?s:s},
$ie:1}
A.eI.prototype={}
A.he.prototype={
k(a,b){var t,s=this.b
if(s==null)return this.c.k(0,b)
else if(typeof b!="string")return null
else{t=s[b]
return typeof t=="undefined"?this.h8(b):t}},
gt(a){return this.b==null?this.c.a:this.cM().length},
gaU(a){return this.gt(0)===0},
gbw(){if(this.b==null){var t=this.c
return new A.bj(t,A.l(t).v("bj<1>"))}return new A.hf(this)},
aT(a,b){var t,s,r,q,p=this
u.cA.a(b)
if(p.b==null)return p.c.aT(0,b)
t=p.cM()
for(s=0;s<t.length;++s){r=t[s]
q=p.b[r]
if(typeof q=="undefined"){q=A.j1(p.a[r])
p.b[r]=q}b.$2(r,q)
if(t!==p.c)throw A.f(A.b2(p))}},
cM(){var t=u.M.a(this.c)
if(t==null)t=this.c=A.j(Object.keys(this.a),u.s)
return t},
h8(a){var t
if(!Object.prototype.hasOwnProperty.call(this.a,a))return null
t=A.j1(this.a[a])
return this.b[a]=t}}
A.hf.prototype={
gt(a){return this.a.gt(0)},
bv(a,b){var t=this.a
if(t.b==null)t=t.gbw().bv(0,b)
else{t=t.cM()
if(!(b>=0&&b<t.length))return A.a(t,b)
t=t[b]}return t},
gI(a){var t=this.a
if(t.b==null){t=t.gbw()
t=t.gI(t)}else{t=t.cM()
t=new J.bR(t,t.length,A.al(t).v("bR<1>"))}return t}}
A.iX.prototype={
$0(){var t,s
try{t=new TextDecoder("utf-8",{fatal:true})
return t}catch(s){}return null},
$S:11}
A.iW.prototype={
$0(){var t,s
try{t=new TextDecoder("utf-8",{fatal:false})
return t}catch(s){}return null},
$S:11}
A.iS.prototype={
cm(a){var t,s,r,q
u.L.a(a)
t=a.length
s=A.aZ(0,null,t)
for(r=0;r<s;++r){if(!(r<t))return A.a(a,r)
q=a[r]
if((q&4294967040)!==0){if(!this.a)throw A.f(A.hD("Invalid value in input: "+q,null,null))
return this.h9(a,0,s)}}return A.en(a,0,s)},
h9(a,b,c){var t,s,r,q
u.L.a(a)
for(t=a.length,s=b,r="";s<c;++s){if(!(s<t))return A.a(a,s)
q=a[s]
r+=A.W((q&4294967040)!==0?65533:q)}return r.charCodeAt(0)==0?r:r}}
A.bS.prototype={}
A.eZ.prototype={}
A.f_.prototype={}
A.dQ.prototype={
D(a){var t=A.f0(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+t}}
A.fD.prototype={
D(a){return"Cyclic error in JSON stringify"}}
A.fC.prototype={
f0(a,b){var t=A.px(a,this.gj6().a)
return t},
d4(a,b){var t=A.oB(a,this.gj9().b,null)
return t},
gj9(){return B.db},
gj6(){return B.da}}
A.hY.prototype={}
A.hX.prototype={}
A.iP.prototype={
fk(a){var t,s,r,q,p,o,n=a.length
for(t=this.c,s=0,r=0;r<n;++r){q=a.charCodeAt(r)
if(q>92){if(q>=55296){p=q&64512
if(p===55296){o=r+1
o=!(o<n&&(a.charCodeAt(o)&64512)===56320)}else o=!1
if(!o)if(p===56320){p=r-1
p=!(p>=0&&(a.charCodeAt(p)&64512)===55296)}else p=!1
else p=!0
if(p){if(r>s)t.a+=B.p.cI(a,s,r)
s=r+1
p=A.W(92)
t.a+=p
p=A.W(117)
t.a+=p
p=A.W(100)
t.a+=p
p=q>>>8&15
p=A.W(p<10?48+p:87+p)
t.a+=p
p=q>>>4&15
p=A.W(p<10?48+p:87+p)
t.a+=p
p=q&15
p=A.W(p<10?48+p:87+p)
t.a+=p}}continue}if(q<32){if(r>s)t.a+=B.p.cI(a,s,r)
s=r+1
p=A.W(92)
t.a+=p
switch(q){case 8:p=A.W(98)
t.a+=p
break
case 9:p=A.W(116)
t.a+=p
break
case 10:p=A.W(110)
t.a+=p
break
case 12:p=A.W(102)
t.a+=p
break
case 13:p=A.W(114)
t.a+=p
break
default:p=A.W(117)
t.a+=p
p=A.W(48)
t.a=(t.a+=p)+p
p=q>>>4&15
p=A.W(p<10?48+p:87+p)
t.a+=p
p=q&15
p=A.W(p<10?48+p:87+p)
t.a+=p
break}}else if(q===34||q===92){if(r>s)t.a+=B.p.cI(a,s,r)
s=r+1
p=A.W(92)
t.a+=p
p=A.W(q)
t.a+=p}}if(s===0)t.a+=a
else if(s<n)t.a+=B.p.cI(a,s,n)},
de(a){var t,s,r,q
for(t=this.a,s=t.length,r=0;r<s;++r){q=t[r]
if(a==null?q==null:a===q)throw A.f(new A.fD(a,null))}B.c.A(t,a)},
d8(a){var t,s,r,q,p=this
if(p.fj(a))return
p.de(a)
try{t=p.b.$1(a)
if(!p.fj(t)){r=A.lp(a,null,p.geu())
throw A.f(r)}r=p.a
if(0>=r.length)return A.a(r,-1)
r.pop()}catch(q){s=A.kH(q)
r=A.lp(a,s,p.geu())
throw A.f(r)}},
fj(a){var t,s,r=this
if(typeof a=="number"){if(!isFinite(a))return!1
r.c.a+=B.b.D(a)
return!0}else if(a===!0){r.c.a+="true"
return!0}else if(a===!1){r.c.a+="false"
return!0}else if(a==null){r.c.a+="null"
return!0}else if(typeof a=="string"){t=r.c
t.a+='"'
r.fk(a)
t.a+='"'
return!0}else if(u.j.b(a)){r.de(a)
r.jH(a)
t=r.a
if(0>=t.length)return A.a(t,-1)
t.pop()
return!0}else if(u.f.b(a)){r.de(a)
s=r.jI(a)
t=r.a
if(0>=t.length)return A.a(t,-1)
t.pop()
return s}else return!1},
jH(a){var t,s,r=this.c
r.a+="["
t=J.S(a)
if(t.gdK(a)){this.d8(t.k(a,0))
for(s=1;s<t.gt(a);++s){r.a+=","
this.d8(t.k(a,s))}}r.a+="]"},
jI(a){var t,s,r,q,p,o,n=this,m={}
if(a.gaU(a)){n.c.a+="{}"
return!0}t=a.gt(a)*2
s=A.P(t,null,!1,u.X)
r=m.a=0
m.b=!0
a.aT(0,new A.iQ(m,s))
if(!m.b)return!1
q=n.c
q.a+="{"
for(p='"';r<t;r+=2,p=',"'){q.a+=p
n.fk(A.b0(s[r]))
q.a+='":'
o=r+1
if(!(o<t))return A.a(s,o)
n.d8(s[o])}q.a+="}"
return!0}}
A.iQ.prototype={
$2(a,b){var t,s
if(typeof a!="string")this.a.b=!1
t=this.b
s=this.a
B.c.i(t,s.a++,a)
B.c.i(t,s.a++,b)},
$S:10}
A.iO.prototype={
geu(){var t=this.c.a
return t.charCodeAt(0)==0?t:t}}
A.fE.prototype={
bO(a){var t
u.L.a(a)
t=B.dc.cm(a)
return t}}
A.hZ.prototype={}
A.h5.prototype={
f_(a,b){u.L.a(a)
return(b===!0?B.kN:B.kM).cm(a)}}
A.ip.prototype={
cm(a){var t,s,r,q=a.length,p=A.aZ(0,null,q)
if(p===0)return new Uint8Array(0)
t=new Uint8Array(p*3)
s=new A.iY(t)
if(s.hK(a,0,p)!==p){r=p-1
if(!(r>=0&&r<q))return A.a(a,r)
s.dD()}return B.e.b6(t,0,s.b)}}
A.iY.prototype={
dD(){var t,s=this,r=s.c,q=s.b,p=s.b=q+1
r.$flags&2&&A.b(r)
t=r.length
if(!(q<t))return A.a(r,q)
r[q]=239
q=s.b=p+1
if(!(p<t))return A.a(r,p)
r[p]=191
s.b=q+1
if(!(q<t))return A.a(r,q)
r[q]=189},
iS(a,b){var t,s,r,q,p,o=this
if((b&64512)===56320){t=65536+((a&1023)<<10)|b&1023
s=o.c
r=o.b
q=o.b=r+1
s.$flags&2&&A.b(s)
p=s.length
if(!(r<p))return A.a(s,r)
s[r]=t>>>18|240
r=o.b=q+1
if(!(q<p))return A.a(s,q)
s[q]=t>>>12&63|128
q=o.b=r+1
if(!(r<p))return A.a(s,r)
s[r]=t>>>6&63|128
o.b=q+1
if(!(q<p))return A.a(s,q)
s[q]=t&63|128
return!0}else{o.dD()
return!1}},
hK(a,b,c){var t,s,r,q,p,o,n,m,l=this
if(b!==c){t=c-1
if(!(t>=0&&t<a.length))return A.a(a,t)
t=(a.charCodeAt(t)&64512)===55296}else t=!1
if(t)--c
for(t=l.c,s=t.$flags|0,r=t.length,q=a.length,p=b;p<c;++p){if(!(p<q))return A.a(a,p)
o=a.charCodeAt(p)
if(o<=127){n=l.b
if(n>=r)break
l.b=n+1
s&2&&A.b(t)
t[n]=o}else{n=o&64512
if(n===55296){if(l.b+4>r)break
n=p+1
if(!(n<q))return A.a(a,n)
if(l.iS(o,a.charCodeAt(n)))p=n}else if(n===56320){if(l.b+3>r)break
l.dD()}else if(o<=2047){n=l.b
m=n+1
if(m>=r)break
l.b=m
s&2&&A.b(t)
if(!(n<r))return A.a(t,n)
t[n]=o>>>6|192
l.b=m+1
t[m]=o&63|128}else{n=l.b
if(n+2>=r)break
m=l.b=n+1
s&2&&A.b(t)
if(!(n<r))return A.a(t,n)
t[n]=o>>>12|224
n=l.b=m+1
if(!(m<r))return A.a(t,m)
t[m]=o>>>6&63|128
l.b=n+1
if(!(n<r))return A.a(t,n)
t[n]=o&63|128}}}return p}}
A.h6.prototype={
cm(a){return new A.hi(this.a).e4(u.L.a(a),0,null,!0)}}
A.hi.prototype={
e4(a,b,c,d){var t,s,r,q,p,o,n,m=this
u.L.a(a)
t=A.aZ(b,c,a.length)
if(b===t)return""
if(a instanceof Uint8Array){s=a
r=s
q=0}else{r=A.oT(a,b,t)
t-=b
q=b
b=0}if(t-b>=15){p=m.a
o=A.oS(p,r,b,t)
if(o!=null){if(!p)return o
if(o.indexOf("\ufffd")<0)return o}}o=m.di(r,b,t,!0)
p=m.b
if((p&1)!==0){n=A.oU(p)
m.b=0
throw A.f(A.hD(n,a,q+m.c))}return o},
di(a,b,c,d){var t,s,r=this
if(c-b>1000){t=B.a.Y(b+c,2)
s=r.di(a,b,t,!1)
if((r.b&1)!==0)return s
return s+r.di(a,t,c,d)}return r.j2(a,b,c,d)},
j2(a,b,c,a0){var t,s,r,q,p,o,n,m,l=this,k="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFFFFFFFFFFFFFFFGGGGGGGGGGGGGGGGHHHHHHHHHHHHHHHHHHHHHHHHHHHIHHHJEEBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKCCCCCCCCCCCCDCLONNNMEEEEEEEEEEE",j=" \x000:XECCCCCN:lDb \x000:XECCCCCNvlDb \x000:XECCCCCN:lDb AAAAA\x00\x00\x00\x00\x00AAAAA00000AAAAA:::::AAAAAGG000AAAAA00KKKAAAAAG::::AAAAA:IIIIAAAAA000\x800AAAAA\x00\x00\x00\x00 AAAAA",i=65533,h=l.b,g=l.c,f=new A.cm(""),e=b+1,d=a.length
if(!(b>=0&&b<d))return A.a(a,b)
t=a[b]
A:for(s=l.a;;){for(;;e=p){if(!(t>=0&&t<256))return A.a(k,t)
r=k.charCodeAt(t)&31
g=h<=32?t&61694>>>r:(t&63|g<<6)>>>0
q=h+r
if(!(q>=0&&q<144))return A.a(j,q)
h=j.charCodeAt(q)
if(h===0){q=A.W(g)
f.a+=q
if(e===c)break A
break}else if((h&1)!==0){if(s)switch(h){case 69:case 67:q=A.W(i)
f.a+=q
break
case 65:q=A.W(i)
f.a+=q;--e
break
default:q=A.W(i)
f.a=(f.a+=q)+q
break}else{l.b=h
l.c=e-1
return""}h=0}if(e===c)break A
p=e+1
if(!(e>=0&&e<d))return A.a(a,e)
t=a[e]}p=e+1
if(!(e>=0&&e<d))return A.a(a,e)
t=a[e]
if(t<128){for(;;){if(!(p<c)){o=c
break}n=p+1
if(!(p>=0&&p<d))return A.a(a,p)
t=a[p]
if(t>=128){o=n-1
p=n
break}p=n}if(o-e<20)for(m=e;m<o;++m){if(!(m<d))return A.a(a,m)
q=A.W(a[m])
f.a+=q}else{q=A.en(a,e,o)
f.a+=q}if(o===c)break A
e=p}else e=p}if(a0&&h>32)if(s){d=A.W(i)
f.a+=d}else{l.b=77
l.c=c
return""}l.b=h
l.c=g
d=f.a
return d.charCodeAt(0)==0?d:d}}
A.iJ.prototype={
D(a){return this.ad()}}
A.T.prototype={}
A.eO.prototype={
D(a){var t=this.a
if(t!=null)return"Assertion failed: "+A.f0(t)
return"Assertion failed"}}
A.er.prototype={}
A.bb.prototype={
gdl(){return"Invalid argument"+(!this.a?"(s)":"")},
gdk(){return""},
D(a){var t=this,s=t.c,r=s==null?"":" ("+s+")",q=t.d,p=q==null?"":": "+A.z(q),o=t.gdl()+r+p
if(!t.a)return o
return o+t.gdk()+": "+A.f0(t.gdJ())},
gdJ(){return this.b}}
A.d7.prototype={
gdJ(){return A.Q(this.b)},
gdl(){return"RangeError"},
gdk(){var t,s=this.e,r=this.f
if(s==null)t=r!=null?": Not less than or equal to "+A.z(r):""
else if(r==null)t=": Not greater than or equal to "+A.z(s)
else if(r>s)t=": Not in inclusive range "+A.z(s)+".."+A.z(r)
else t=r<s?": Valid value range is empty":": Only valid value is "+A.z(s)
return t}}
A.fh.prototype={
gdJ(){return A.u(this.b)},
gdl(){return"RangeError"},
gdk(){if(A.u(this.b)<0)return": index must not be negative"
var t=this.f
if(t===0)return": no indices are valid"
return": index should be less than "+t},
gt(a){return this.f}}
A.es.prototype={
D(a){return"Unsupported operation: "+this.a}}
A.h3.prototype={
D(a){return"UnimplementedError: "+this.a}}
A.da.prototype={
D(a){return"Bad state: "+this.a}}
A.eX.prototype={
D(a){var t=this.a
if(t==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.f0(t)+"."}}
A.fF.prototype={
D(a){return"Out of Memory"},
$iT:1}
A.em.prototype={
D(a){return"Stack Overflow"},
$iT:1}
A.iK.prototype={
D(a){return"Exception: "+this.a}}
A.hC.prototype={
D(a){var t=this.a,s=""!==t?"FormatException: "+t:"FormatException",r=this.c
return r!=null?s+(" (at offset "+A.z(r)+")"):s}}
A.e.prototype={
gt(a){var t,s=this.gI(this)
for(t=0;s.F();)++t
return t},
bv(a,b){var t,s
A.d8(b,"index")
t=this.gI(this)
for(s=b;t.F();){if(s===0)return t.gM();--s}throw A.f(A.jV(b,b-s,this,"index"))},
D(a){return A.nj(this,"(",")")}}
A.e1.prototype={
gH(a){return A.H.prototype.gH.call(this,0)},
D(a){return"null"}}
A.H.prototype={$iH:1,
S(a,b){return this===b},
gH(a){return A.ei(this)},
D(a){return"Instance of '"+A.fL(this)+"'"},
gaE(a){return A.q6(this)},
toString(){return this.D(this)}}
A.cm.prototype={
gt(a){return this.a.length},
D(a){var t=this.a
return t.charCodeAt(0)==0?t:t},
$inL:1}
A.db.prototype={
ad(){return"ToeEnd."+this.b}}
A.hG.prototype={}
A.hF.prototype={}
A.a7.prototype={
D(a){return this.a}}
A.iM.prototype={
bc(a){var t=this.a,s=u.j
return s.b(t.k(0,a))?s.a(t.k(0,a)):B.J},
b_(a,b){var t,s=this.bc(a)
if(b>=0){t=J.S(s)
t=b>=t.gt(s)||!u.f.b(t.k(s,b))}else t=!0
if(t)return A.D(u.N,u.z)
return A.b3(u.f.a(J.c(s,b)),u.N,u.z)}}
A.jd.prototype={
$1(a){return J.ac(a)},
$S:7}
A.je.prototype={
$1(a){return J.ac(a)},
$S:7}
A.iL.prototype={
d3(){var t,s,r,q,p,o,n,m,l,k
for(t=this.a,s=t.length,r=1/0,q=1/0,p=1/0,o=-1/0,n=-1/0,m=-1/0,l=0;l<s;l+=3){k=t[l]
r=Math.min(r,k)
o=Math.max(o,k)
k=l+1
if(!(k<s))return A.a(t,k)
k=t[k]
q=Math.min(q,k)
n=Math.max(n,k)
k=l+2
if(!(k<s))return A.a(t,k)
k=t[k]
p=Math.min(p,k)
m=Math.max(m,k)}return A.j([r,q,p,o,n,m],u.n)}}
A.j9.prototype={
$1(a){return A.u(a)>=this.a},
$S:21}
A.j4.prototype={
$1(a){return A.bK(a)},
$S:5}
A.j5.prototype={
$1(a){return A.bK(a)},
$S:5}
A.j6.prototype={
$1(a){return A.bK(a)},
$S:5}
A.j7.prototype={
$1(a){return A.bK(a)},
$S:5}
A.jf.prototype={
$1(a){return B.b.h(A.bK(a))},
$S:24}
A.jh.prototype={
$2(a,b){var t,s,r,q=this
u.H.a(b)
if(a<0||a>=J.ao(q.a))return
t=A.b3(u.f.a(J.c(q.a,a)),u.N,u.z)
s=A.pt(b,A.pv(t))
if(t.k(0,"mesh")!=null)B.c.A(q.b,s)
r=u.M.a(t.k(0,"children"))
r=J.bu(r==null?B.J:r)
while(r.F())q.$2(B.b.h(A.bK(r.gM())),s)},
$S:26}
A.jg.prototype={
$1(a){var t,s,r
u.H.a(a)
for(t=J.S(a),s=this.a,r=0;r<12;++r)if(Math.abs(t.k(a,r)-B.c.gdI(s)[r])>1e-9)return!0
return!1},
$S:15}
A.ha.prototype={}
A.aF.prototype={}
A.ja.prototype={
$2(a,b){var t,s
if(a>=0&&a<this.a.length){t=this.a
if(!(a>=0&&a<t.length))return A.a(t,a)
s=t[a]}else s="upper"
B.c.A(this.c.fa(s,new A.jb(s,a)).c,b)},
$S:30}
A.jb.prototype={
$0(){return new A.aF(this.a,this.b,A.j([],u.t))},
$S:34}
A.jc.prototype={
$1(a){return u.E.a(a).c.length!==0},
$S:35}
A.jj.prototype={
$2$stride(a,b){var t,s,r
u.L.a(a)
for(t=this.a;B.a.a1(t.gt(t),4)!==0;)t.eM(0)
s=t.gt(t)
t.A(0,a)
r=A.aD(["buffer",0,"byteOffset",s,"byteLength",t.gt(t)-s],u.N,u.z)
if(b>0)r.i(0,"byteStride",b)
t=this.b
B.c.A(t,r)
return t.length-1},
$S:16}
A.jo.prototype={
$1(a){var t,s,r
u.H.a(a)
t=a.length
s=new DataView(new ArrayBuffer(t*4))
for(r=0;r<a.length;++r)s.setFloat32(r*4,a[r],!0)
return J.ab(B.W.gB(s))},
$S:17}
A.jp.prototype={
$2(a,b){var t,s,r
u.L.a(a)
t=a.length
s=new DataView(new ArrayBuffer(t*b))
for(t=b===2,r=0;r<a.length;++r)if(t)s.setUint16(r*2,a[r],!0)
else s.setUint32(r*4,a[r],!0)
return J.ab(B.W.gB(s))},
$S:18}
A.jk.prototype={
$0(){var t,s,r,q=this,p=q.a,o=p.length,n=q.b,m=n.a,l=q.c,k=l*3
if(!(k>=0&&k<m.length))return A.a(m,k)
B.c.A(p,m[k])
t=k+1
if(!(t<m.length))return A.a(m,t)
B.c.A(p,m[t])
s=k+2
if(!(s<m.length))return A.a(m,s)
B.c.A(p,m[s])
p=n.b
m=p.length
if(m!==0){r=q.d
if(!(k<m))return A.a(p,k)
B.c.A(r,p[k])
if(!(t<p.length))return A.a(p,t)
B.c.A(r,p[t])
if(!(s<p.length))return A.a(p,s)
B.c.A(r,p[s])}p=n.c
n=p.length
if(n!==0){m=q.e
l*=2
if(!(l>=0&&l<n))return A.a(p,l)
B.c.A(m,p[l]);++l
if(!(l<p.length))return A.a(p,l)
B.c.A(m,p[l])}return o/3|0},
$S:19}
A.jl.prototype={
$2(a,b){var t=J.bt(a)
if(B.c5.aR(0,t.D(a)))return
this.a.i(0,t.D(a),b)
this.b.A(0,t.D(a))},
$S:6}
A.jm.prototype={
$1(a){return A.b3(u.f.a(a),u.N,u.z)},
$S:12}
A.jn.prototype={
$1(a){return A.b3(u.f.a(a),u.N,u.z)},
$S:12}
A.j2.prototype={
$1(a){var t=u.f.a(a).k(0,"name")
t=t==null?null:J.ac(t)
return t==null?"":t},
$S:7}
A.hH.prototype={
fI(a){var t,s,r,q,p,o,n,m,l,k,j,i,h=this,g=a.length
for(t=0;t<g;++t){s=a[t]
if(s>h.b)h.b=s
if(s<h.c)h.c=s}s=h.b
r=B.a.W(1,s)
q=h.a=new Uint32Array(r)
for(p=1,o=0,n=2;p<=s;){for(m=p<<16,t=0;t<g;++t)if(a[t]===p){for(l=o,k=0,j=0;j<p;++j){k=(k<<1|l&1)>>>0
l=l>>>1}for(i=(m|t)>>>0,j=k;j<r;j+=n){if(!(j>=0))return A.a(q,j)
q[j]=i}++o}++p
o=o<<1>>>0
n=n<<1>>>0}}}
A.iG.prototype={}
A.j_.prototype={
j4(a,b,c,d){var t,s,r,q,p,o,n=null
for(;;){t=a.c
s=a.d
s===$&&A.d()
if(!(t<s))break
s=a.b
s.toString
r=a.c=t+1
q=s.length
if(!(t>=0&&t<q))return A.a(s,t)
p=s[t]
a.c=r+1
if(!(r>=0&&r<q))return A.a(s,r)
o=s[r]
if((p&8)!==8)return!1
if(B.a.a1(p*256+o,31)!==0)return!1
if((o>>>5&1)!==0){a.l()
return!1}if(n!=null)b.aV(n)
t=new A.e4(new Uint8Array(32768),B.ap)
new A.hP(a,t).hS()
n=J.V(B.e.gB(t.c),t.c.byteOffset,t.b)
a.l()}if(n!=null)b.aV(n)
return!0}}
A.hP.prototype={
gbt(){var t=this.a
if(t==null)return t
t.d===$&&A.d()
return t},
hS(){var t,s,r=this
r.e=r.d=0
if(r.gbt()==null)return
for(;;){t=r.gbt()
s=t.c
t=t.d
t===$&&A.d()
if(!(s<t))break
if(!r.i2())return}},
i2(){var t,s,r,q=this,p=q.gbt()
if(p!=null){t=p.c
s=p.d
s===$&&A.d()
s=t>=s
t=s}else t=!0
if(t)return!1
r=q.ba(3)
switch(B.a.j(r,1)){case 0:if(q.ic()===-1)return!1
break
case 1:if(q.e8($.mq(),$.mp())===-1)return!1
break
case 2:if(q.i3()===-1)return!1
break
default:return!1}return(r&1)===0},
ba(a){var t,s,r,q,p=this
if(a===0)return 0
while(t=p.e,t<a){t=p.gbt()
s=t.c
t=t.d
t===$&&A.d()
if(s>=t)return-1
t=p.gbt()
s=t.b
s.toString
t=t.c++
if(!(t>=0&&t<s.length))return A.a(s,t)
r=s[t]
t=p.d
s=p.e
p.d=(t|B.a.W(r,s))>>>0
p.e=s+8}s=p.d
q=B.a.O(1,a)
p.d=B.a.a_(s,a)
p.e=t-a
return(s&q-1)>>>0},
dz(a){var t,s,r,q,p,o,n,m=this,l=a.a
l===$&&A.d()
t=a.b
while(s=m.e,s<t){s=m.gbt()
r=s.c
s=s.d
s===$&&A.d()
if(r>=s)return-1
s=m.gbt()
r=s.b
r.toString
s=s.c++
if(!(s>=0&&s<r.length))return A.a(r,s)
q=r[s]
s=m.d
r=m.e
m.d=(s|B.a.W(q,r))>>>0
m.e=r+8}r=m.d
p=(r&B.a.W(1,t)-1)>>>0
if(!(p<l.length))return A.a(l,p)
o=l[p]
n=o>>>16
m.d=B.a.a_(r,n)
m.e=s-n
return o&65535},
ic(){var t,s,r=this
r.e=r.d=0
t=r.ba(16)
s=r.ba(16)
if(t!==0&&t!==(s^65535)>>>0)return-1
if(t>r.gbt().gt(0))return-1
r.c.jJ(r.gbt().ag(t))
return 0},
i3(){var t,s,r,q,p,o,n,m,l,k,j=this,i=j.ba(5)
if(i===-1)return-1
i+=257
if(i>288)return-1
t=j.ba(5)
if(t===-1)return-1;++t
if(t>32)return-1
s=j.ba(4)
if(s===-1)return-1
s+=4
if(s>19)return-1
r=new Uint8Array(19)
for(q=0;q<s;++q){p=j.ba(3)
if(p===-1)return-1
o=B.iS[q]
if(!(o<19))return A.a(r,o)
r[o]=p}n=A.fa(r)
o=i+t
m=new Uint8Array(o)
l=J.V(B.e.gB(m),0,i)
k=J.V(B.e.gB(m),i,t)
if(j.hb(o,n,m)===-1)return-1
return j.e8(A.fa(l),A.fa(k))},
e8(a,b){var t,s,r,q,p,o,n,m,l=this
for(t=l.c;;){s=l.dz(a)
if(s<0||s>285)return-1
if(s===256)break
if(s<256){t.C(s&255)
continue}r=s-257
if(!(r>=0&&r<29))return A.a(B.bH,r)
q=B.bH[r]+l.ba(B.jM[r])
p=l.dz(b)
if(p<0||p>29)return-1
if(!(p>=0&&p<30))return A.a(B.bI,p)
o=B.bI[p]+l.ba(B.fn[p])
for(n=-o;q>o;){t.aV(t.ai(n))
q-=o}if(q===o)t.aV(t.ai(n))
else t.aV(t.dS(n,q-o))}while(t=l.e,t>=8){l.e=t-8
t=l.gbt()
n=--t.c
m=t.d
m===$&&A.d()
t.c=B.a.J(n,0,m)}return 0},
hb(a,b,c){var t,s,r,q,p,o,n,m,l=this
for(t=0,s=0;s<a;){r=l.dz(b)
if(r===-1)return-1
q=0
switch(r){case 16:p=l.ba(2)
if(p===-1)return-1
p+=3
for(o=c.$flags|0;n=p-1,p>0;p=n,s=m){m=s+1
o&2&&A.b(c)
if(!(s>=0&&s<c.length))return A.a(c,s)
c[s]=t}break
case 17:p=l.ba(3)
if(p===-1)return-1
p+=3
for(o=c.$flags|0;n=p-1,p>0;p=n,s=m){m=s+1
o&2&&A.b(c)
if(!(s>=0&&s<c.length))return A.a(c,s)
c[s]=0}t=q
break
case 18:p=l.ba(7)
if(p===-1)return-1
p+=11
for(o=c.$flags|0;n=p-1,p>0;p=n,s=m){m=s+1
o&2&&A.b(c)
if(!(s>=0&&s<c.length))return A.a(c,s)
c[s]=0}t=q
break
default:if(r<0||r>15)return-1
m=s+1
c.$flags&2&&A.b(c)
if(!(s>=0&&s<c.length))return A.a(c,s)
c[s]=r
s=m
t=r
break}}return 0}}
A.iF.prototype={
bP(a){var t
u.L.a(a)
t=A.nC(B.ap,32768)
B.cB.j4(A.jW(a,B.aM,null,null),t,!1,!1)
return t.fl()}}
A.eS.prototype={
ad(){return"ByteOrder."+this.b}}
A.fi.prototype={
gt(a){var t=this.b
return t==null?0:t.length-this.c},
fB(a,b){var t=this.b
if(t==null)return A.jW(A.j([],u.t),B.ap,null,null)
return A.jW(t,this.a,a,b)},
G(){var t,s=this.b
s.toString
t=this.c++
if(!(t>=0&&t<s.length))return A.a(s,t)
return s[t]}}
A.fj.prototype={
l(){var t=this,s=t.G(),r=t.G(),q=t.G(),p=t.G()
if(t.a===B.aM)return(s<<24|r<<16|q<<8|p)>>>0
return(p<<24|q<<16|r<<8|s)>>>0},
ag(a){var t=this,s=t.fB(a,t.c)
t.c=t.c+s.gt(0)
return s}}
A.e4.prototype={
fl(){return J.V(B.e.gB(this.c),this.c.byteOffset,this.b)},
C(a){var t,s,r=this
if(r.b===r.c.length)r.i1()
t=r.c
s=r.b++
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=a},
jE(a,b){var t,s,r,q,p=this
u.L.a(a)
if(b==null)b=a.length
while(t=p.b,s=t+b,r=p.c,q=r.length,s>q)p.du(s-q)
B.e.bk(r,t,s,a)
p.b+=b},
aV(a){return this.jE(a,null)},
jJ(a){var t,s,r,q,p,o,n=this
for(;;){t=n.b
s=a.b
r=s==null
q=r?0:s.length-a.c
p=n.c
o=p.length
if(!(t+q>o))break
n.du(t+(r?0:s.length-a.c)-o)}if(!r)B.e.ar(p,t,t+a.gt(0),s,a.c)
n.b=n.b+a.gt(0)},
dS(a,b){var t=this
if(a<0)a=t.b+a
if(b==null)b=t.b
else if(b<0)b=t.b+b
return J.V(B.e.gB(t.c),t.c.byteOffset+a,b-a)},
ai(a){return this.dS(a,null)},
du(a){var t=a!=null?a>32768?a:32768:32768,s=this.c,r=s.length,q=new Uint8Array((r+t)*2)
B.e.bk(q,0,r,s)
this.c=q},
i1(){return this.du(null)},
gt(a){return this.b}}
A.fG.prototype={}
A.hu.prototype={
ad(){return"Channel."+this.b}}
A.L.prototype={
F(){var t=this.b
return++this.a<t.gt(t)},
gM(){return this.b.k(0,this.a)},
$iA:1}
A.cz.prototype={
P(){return new A.cz(new Uint16Array(A.w(this.a)))},
gK(){return B.C},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=A.I(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){return this.gn()},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=A.I(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t,s=this.a
if(s.length>1){s=s[1]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
sp(a){var t,s=this.a
if(s.length>1){t=A.I(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t,s=this.a
if(s.length>2){s=s[2]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
sq(a){var t,s=this.a
if(s.length>2){t=A.I(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t,s=this.a
if(s.length>3){s=s[3]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
gU(){return this.gu()/1},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=A.I(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cA.prototype={
P(){return new A.cA(new Float32Array(A.w(this.a)))},
gK(){return B.H},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t=this.a,s=t.length
if(b<s){t.$flags&2&&A.b(t)
if(!(b>=0))return A.a(t,b)
t[b]=c}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t=this.a,s=t.length
if(s!==0){t.$flags&2&&A.b(t)
if(0>=s)return A.a(t,0)
t[0]=a}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t=this.a
if(t.length>1){t.$flags&2&&A.b(t)
t[1]=a}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t=this.a
if(t.length>2){t.$flags&2&&A.b(t)
t[2]=a}},
gu(){var t=this.a
return t.length>3?t[3]:1},
gU(){return this.gu()/1},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cB.prototype={
P(){return new A.cB(new Float64Array(A.w(this.a)))},
gK(){return B.L},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t=this.a,s=t.length
if(b<s){t.$flags&2&&A.b(t)
if(!(b>=0))return A.a(t,b)
t[b]=c}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t=this.a,s=t.length
if(s!==0){t.$flags&2&&A.b(t)
if(0>=s)return A.a(t,0)
t[0]=a}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t=this.a
if(t.length>1){t.$flags&2&&A.b(t)
t[1]=a}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t=this.a
if(t.length>2){t.$flags&2&&A.b(t)
t[2]=a}},
gu(){var t=this.a
return t.length>3?t[3]:1},
gU(){return this.gu()/1},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cC.prototype={
P(){return new A.cC(new Int16Array(A.w(this.a)))},
gK(){return B.N},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=B.b.h(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:0},
gU(){return this.gu()/32767},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cD.prototype={
P(){return new A.cD(new Int32Array(A.w(this.a)))},
gK(){return B.O},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t=this.a,s=t.length
if(s!==0){A.u(a)
t.$flags&2&&A.b(t)
if(0>=s)return A.a(t,0)
t[0]=a}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:0},
gU(){return this.gu()/2147483647},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cE.prototype={
P(){return new A.cE(new Int8Array(A.w(this.a)))},
gK(){return B.M},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=B.b.h(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:0},
gU(){return this.gu()/127},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cF.prototype={
P(){var t=this.b
t===$&&A.d()
return new A.cF(this.a,t)},
gK(){return B.w},
gR(){return null},
bV(a){var t
if(a<this.a){t=this.b
t===$&&A.d()
t=B.a.a0(t,7-a)&1}else t=0
return t},
bK(a,b){var t
if(a>=this.a)return
a=7-a
t=this.b
t===$&&A.d()
this.b=b!==0?(t|B.a.W(1,a))>>>0:(t&~(B.a.W(1,a)&255))>>>0},
k(a,b){return this.bV(b)},
i(a,b,c){return this.bK(b,c)},
gN(){return this.bV(0)},
gn(){return this.bV(0)},
sn(a){this.bK(0,a)},
gp(){return this.bV(1)},
sp(a){this.bK(1,a)},
gq(){return this.bV(2)},
sq(a){this.bK(2,a)},
gu(){return this.bV(3)},
gU(){return this.bV(3)/1},
gaj(){return A.X(this)},
ac(a){this.a8(a.gn(),a.gp(),a.gq(),a.gu())},
a8(a,b,c,d){var t=this
t.bK(0,a)
t.bK(1,b)
t.bK(2,c)
t.bK(3,d)},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1,
gt(a){return this.a}}
A.cG.prototype={
P(){return new A.cG(new Uint16Array(A.w(this.a)))},
gK(){return B.l},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=B.b.h(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:0},
gU(){return this.gu()/65535},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cH.prototype={
P(){var t=this.b
t===$&&A.d()
return new A.cH(this.a,t)},
gK(){return B.y},
gR(){return null},
bW(a){var t
if(a<this.a){t=this.b
t===$&&A.d()
t=B.a.a0(t,6-(a<<1>>>0))&3}else t=0
return t},
bL(a,b){var t,s,r
if(a>=this.a)return
if(!(a>=0&&a<4))return A.a(B.bd,a)
t=B.bd[a]
s=B.b.h(b)
r=this.b
r===$&&A.d()
this.b=(r&t|B.a.W(s&3,6-(a<<1>>>0)))>>>0},
k(a,b){return this.bW(b)},
i(a,b,c){return this.bL(b,c)},
gN(){return this.bW(0)},
gn(){return this.bW(0)},
sn(a){this.bL(0,a)},
gp(){return this.bW(1)},
sp(a){this.bL(1,a)},
gq(){return this.bW(2)},
sq(a){this.bL(2,a)},
gu(){return this.bW(3)},
gU(){return this.bW(3)/3},
gaj(){return A.X(this)},
ac(a){this.a8(a.gn(),a.gp(),a.gq(),a.gu())},
a8(a,b,c,d){var t=this
t.bL(0,a)
t.bL(1,b)
t.bL(2,c)
t.bL(3,d)},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1,
gt(a){return this.a}}
A.cI.prototype={
P(){return new A.cI(new Uint32Array(A.w(this.a)))},
gK(){return B.I},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=B.b.h(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:0},
gU(){return this.gu()/4294967295},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.cJ.prototype={
P(){return new A.cJ(this.a,new Uint8Array(A.w(this.b)))},
gK(){return B.z},
gR(){return null},
bX(a){var t,s
if(a<0||a>=this.a)t=0
else{t=this.b
s=t.length
if(a<2){if(0>=s)return A.a(t,0)
t=B.a.a0(t[0],4-(a<<2>>>0))&15}else{if(1>=s)return A.a(t,1)
t=B.a.a0(t[1],4-((a&1)<<2))&15}}return t},
bN(a,b){var t,s,r,q
if(a>=this.a)return
t=B.a.J(B.b.h(b),0,15)
if(a>1){a&=1
s=1}else s=0
if(a===0){r=this.b
if(!(s<r.length))return A.a(r,s)
q=r[s]
r.$flags&2&&A.b(r)
r[s]=(q&15|t<<4)>>>0}else if(a===1){r=this.b
if(!(s<r.length))return A.a(r,s)
q=r[s]
r.$flags&2&&A.b(r)
r[s]=(q&240|t)>>>0}},
k(a,b){return this.bX(b)},
i(a,b,c){return this.bN(b,c)},
gN(){return this.bX(0)},
gn(){return this.bX(0)},
sn(a){this.bN(0,a)},
gp(){return this.bX(1)},
sp(a){this.bN(1,a)},
gq(){return this.bX(2)},
sq(a){this.bN(2,a)},
gu(){return this.bX(3)},
gU(){return this.bX(3)/15},
gaj(){return A.X(this)},
ac(a){this.a8(a.gn(),a.gp(),a.gq(),a.gu())},
a8(a,b,c,d){var t=this
t.bN(0,a)
t.bN(1,b)
t.bN(2,c)
t.bN(3,d)},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1,
gt(a){return this.a}}
A.aS.prototype={
fD(a,b,c,d){var t,s=this.a
s.$flags&2&&A.b(s)
t=s.length
if(0>=t)return A.a(s,0)
s[0]=a
if(1>=t)return A.a(s,1)
s[1]=b
if(2>=t)return A.a(s,2)
s[2]=c
if(3>=t)return A.a(s,3)
s[3]=d},
P(){return new A.aS(new Uint8Array(A.w(this.a)))},
gK(){return B.f},
gt(a){return this.a.length},
gR(){return null},
k(a,b){var t=this.a,s=t.length
if(b<s){if(!(b>=0))return A.a(t,b)
t=t[b]}else t=0
return t},
i(a,b,c){var t,s=this.a,r=s.length
if(b<r){t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(b>=0))return A.a(s,b)
s[b]=t}},
gN(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
gn(){var t=this.a,s=t.length
if(s!==0){if(0>=s)return A.a(t,0)
t=t[0]}else t=0
return t},
sn(a){var t,s=this.a,r=s.length
if(r!==0){t=B.b.h(a)
s.$flags&2&&A.b(s)
if(0>=r)return A.a(s,0)
s[0]=t}},
gp(){var t=this.a
return t.length>1?t[1]:0},
sp(a){var t,s=this.a
if(s.length>1){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[1]=t}},
gq(){var t=this.a
return t.length>2?t[2]:0},
sq(a){var t,s=this.a
if(s.length>2){t=B.b.h(a)
s.$flags&2&&A.b(s)
s[2]=t}},
gu(){var t=this.a
return t.length>3?t[3]:255},
gU(){return this.gu()/255},
gaj(){return A.X(this)},
ac(a){var t,s,r=this
r.sn(a.gn())
r.sp(a.gp())
r.sq(a.gq())
t=a.gu()
s=r.a
if(s.length>3){t=B.b.h(t)
s.$flags&2&&A.b(s)
s[3]=t}},
gI(a){return new A.L(this)},
S(a,b){var t,s
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===this.a.length){t=b.gH(b)
s=A.q(this,A.l(this).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.eV.prototype={}
A.bT.prototype={}
A.dl.prototype={
P(){return new A.dl(this.a)},
gK(){return B.f},
gt(a){return 4},
gR(){return null},
k(a,b){var t
if(b>=0&&b<4){t=b<<3>>>0
t=B.a.a_((this.a&B.a.O(255,t))>>>0,t)}else t=0
return t},
i(a,b,c){},
ac(a){},
gN(){return this.k(0,0)},
gn(){return this.k(0,0)},
sn(a){},
gp(){return this.k(0,1)},
sp(a){},
gq(){return this.k(0,2)},
sq(a){},
gu(){return this.k(0,3)},
gU(){return this.gu()/255},
gaj(){return A.X(this)},
gI(a){return new A.L(this)},
S(a,b){var t,s,r=this
if(b==null)return!1
t=!1
if(u.G.b(b))if(b.gt(b)===r.gt(r)){t=b.gH(b)
s=A.q(r,A.l(r).v("e.E"))
t=t===A.m(s)}return t},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
$iy:1}
A.eY.prototype={
gu(){return 255},
gU(){return 1},
gt(a){return 3}}
A.ap.prototype={
ad(){return"Format."+this.b}}
A.eQ.prototype={
ad(){return"BlendMode."+this.b}}
A.bw.prototype={
cF(a){var t=$.kM()
if(!t.ae(a))return"<unknown>"
return t.k(0,a).a},
D(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=this
for(t=f.a,s=new A.O(t,t.r,t.e,A.l(t).v("O<1>")),r=u.p,q=u.r,p=u.N,o=u.P,n="";s.F();){m=s.d
n+=m+"\n"
l=t.k(0,m)
for(m=l.a,m=new A.O(m,m.r,m.e,A.l(m).v("O<1>"));m.F();){k=m.d
j=l.k(0,k)
n=j==null?n+("\t"+f.cF(k)+"\n"):n+("\t"+f.cF(k)+": "+j.D(0)+"\n")}for(m=l.b.a,k=new A.O(m,m.r,m.e,A.l(m).v("O<1>"));k.F();){i=k.d
n+=i+"\n"
if(!m.ae(i))m.i(0,i,new A.aC(A.D(r,q),new A.aK(A.D(p,o))))
h=m.k(0,i)
for(i=h.a,i=new A.O(i,i.r,i.e,A.l(i).v("O<1>"));i.F();){g=i.d
j=h.k(0,g)
n=j==null?n+("\t"+f.cF(g)+"\n"):n+("\t"+f.cF(g)+": "+j.D(0)+"\n")}}}return n.charCodeAt(0)==0?n:n},
aG(a8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4=this,a5="exif",a6="interop",a7=a8.b
a8.b=!0
a8.aw(19789)
a8.aw(42)
a8.aF(8)
t=a4.a
if(t.k(0,"ifd0")==null)t.i(0,"ifd0",new A.aC(A.D(u.p,u.r),new A.aK(A.D(u.N,u.P))))
s=t.k(0,"ifd1")
r=a4.b
q=r!=null&&r.length!==0&&s!=null
if(q){s.i(0,513,A.jU(0))
s.i(0,514,A.jU(r.length))}else if(s!=null){p=s.a
p.bT(0,513)
p.bT(0,514)}o=A.j(["ifd0"],u.s)
for(p=new A.O(t,t.r,t.e,A.l(t).v("O<1>"));p.F();){n=p.d
if(n!=="ifd0")B.c.A(o,n)}p=u.N
n=u.p
m=A.D(p,n)
for(l=o.length,k=u.r,j=u.P,i=8,h=0;h<o.length;o.length===l||(0,A.a_)(o),++h){g=o[h]
f=t.k(0,g)
f.toString
m.i(0,g,i)
e=f.b.a
if(e.ae(a5)){d=new Uint32Array(1)
d[0]=0
f.i(0,34665,new A.aU(d))}else f.a.bT(0,34665)
if(e.ae(a6)){d=new Uint32Array(1)
d[0]=0
f.i(0,40965,new A.aU(d))}else f.a.bT(0,40965)
if(e.ae("gps")){d=new Uint32Array(1)
d[0]=0
f.i(0,34853,new A.aU(d))}else f.a.bT(0,34853)
f=f.a
i+=2+12*f.a+4
for(f=new A.aq(f,f.r,f.e,A.l(f).v("aq<2>"));f.F();){d=f.d
c=d.gav().a
if(!(c<14))return A.a(B.t,c)
b=B.t[c]*d.gt(d)
if(b>4)i+=b}for(f=new A.O(e,e.r,e.e,A.l(e).v("O<1>"));f.F();){d=f.d
if(!e.ae(d))e.i(0,d,new A.aC(A.D(n,k),new A.aK(A.D(p,j))))
c=e.k(0,d)
c.toString
m.i(0,d,i)
c=c.a
a=2+12*c.a
for(d=new A.aq(c,c.r,c.e,A.l(c).v("aq<2>"));d.F();){c=d.d
a0=c.gav().a
if(!(a0<14))return A.a(B.t,a0)
b=B.t[a0]*c.gt(c)
if(b>4)a+=b}i+=a}}if(q)s.k(0,513).bj(i)
a1=o.length
for(l=a1-1,a2=0;a2<a1;++a2){if(!(a2<o.length))return A.a(o,a2)
g=o[a2]
a3=t.k(0,g)
f=a3.b.a
if(f.ae(a5)){e=a3.k(0,34665)
e.toString
d=m.k(0,a5)
d.toString
e.bj(d)}if(f.ae(a6)){e=a3.k(0,40965)
e.toString
d=m.k(0,a6)
d.toString
e.bj(d)}if(f.ae("gps")){e=a3.k(0,34853)
e.toString
d=m.k(0,"gps")
d.toString
e.bj(d)}e=m.k(0,g)
e.toString
a4.eK(a8,a3,e+2+12*a3.a.a+4)
if(a2===l)a8.aF(0)
else{e=a2+1
if(!(e<o.length))return A.a(o,e)
e=m.k(0,o[e])
e.toString
a8.aF(e)}a4.eL(a8,a3)
for(e=new A.O(f,f.r,f.e,A.l(f).v("O<1>"));e.F();){d=e.d
if(!f.ae(d))f.i(0,d,new A.aC(A.D(n,k),new A.aK(A.D(p,j))))
c=f.k(0,d)
c.toString
d=m.k(0,d)
d.toString
a4.eK(a8,c,d+2+12*c.a.a)
a4.eL(a8,c)}}if(q)a8.aV(r)
a8.b=a7},
eK(a,b,c){var t,s,r,q,p,o,n=b.a
a.aw(n.a)
for(n=new A.O(n,n.r,n.e,A.l(n).v("O<1>"));n.F();){t=n.d
s=b.k(0,t)
s.toString
r=t===273
q=r&&s.gav()===B.D?B.n:s.gav()
p=r&&s.gav()===B.D?1:s.gt(s)
a.aw(t)
a.aw(q.a)
a.aF(p)
t=s.gav().a
if(!(t<14))return A.a(B.t,t)
o=B.t[t]*s.gt(s)
if(o<=4){s.aG(a)
while(o<4){a.C(0);++o}}else{a.aF(c)
c+=o}}return c},
eL(a,b){var t,s,r
for(t=b.a,t=new A.aq(t,t.r,t.e,A.l(t).v("aq<2>"));t.F();){s=t.d
r=s.gav().a
if(!(r<14))return A.a(B.t,r)
if(B.t[r]*s.gt(s)>4)s.aG(a)}},
bS(c5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,c0,c1,c2=this,c3="Length must be a non-negative integer: ",c4=c5.e
c5.e=!0
t=c5.d
a1=c5.m()
if(a1===18761){c5.e=!1
if(c5.m()!==42){c5.e=c4
return!1}}else if(a1===19789){c5.e=!0
if(c5.m()!==42){c5.e=c4
return!1}}else return!1
s=c5.l()
r=0
a2=c2.a
a3=u.gn
a4=c5.c
a5=u.p
a6=u.r
a7=u.N
a8=u.P
for(;;){a9=s
if(typeof a9!=="number")return a9.fo()
if(!(a9>0))break
try{a9=t
b0=s
if(typeof a9!=="number")return a9.b3()
if(typeof b0!=="number")return A.hn(b0)
b0=a9+b0
c5.d=b0
if(a4-b0<2)break
q=new A.aC(A.D(a5,a6),new A.aK(A.D(a7,a8)))
p=c5.m()
a9=p
if(typeof a9!=="number")return a9.dO()
if(a9*12>a4-c5.d)break
o=p
a9=o
if(a9<0)A.aA(A.bQ(c3+A.z(a9)))
n=A.j(new Array(a9),a3)
m=0
for(;;){a9=m
b0=o
if(typeof a9!=="number")return a9.fp()
if(typeof b0!=="number")return A.hn(b0)
if(!(a9<b0))break
J.x(n,m,c2.ex(c5,t))
a9=m
if(typeof a9!=="number")return a9.b3()
m=a9+1}l=n
for(a9=l,b0=a9.length,b1=0;b1<a9.length;a9.length===b0||(0,A.a_)(a9),++b1){k=a9[b1]
if(k.b!=null){b2=k.a
b3=k.b
b3.toString
J.x(q,b2,b3)}}a2.i(0,"ifd"+A.z(r),q)
a9=r
if(typeof a9!=="number")return a9.b3()
r=a9+1
j=c5.l()
if(J.bO(j,s))break
else s=j}catch(b4){break}}for(a9=new A.aq(a2,a2.r,a2.e,A.l(a2).v("aq<2>"));a9.F();){i=a9.d
for(b0=B.bS.gbw(),b0=b0.gI(b0);b0.F();){h=b0.gM()
b2=A.u(h)
if(i.a.ae(b2))try{g=J.c(i,h).h(0)
b2=t
b3=g
if(typeof b2!=="number")return b2.b3()
if(typeof b3!=="number")return A.hn(b3)
c5.d=b2+b3
f=new A.aC(A.D(a5,a6),new A.aK(A.D(a7,a8)))
e=c5.m()
d=e
b3=d
if(b3<0)A.aA(A.bQ(c3+A.z(b3)))
c=A.j(new Array(b3),a3)
b=0
for(;;){b2=b
b3=d
if(typeof b2!=="number")return b2.fp()
if(typeof b3!=="number")return A.hn(b3)
if(!(b2<b3))break
J.x(c,b,c2.ex(c5,t))
b2=b
if(typeof b2!=="number")return b2.b3()
b=b2+1}a=c
for(b2=a,b3=b2.length,b1=0;b1<b2.length;b2.length===b3||(0,A.a_)(b2),++b1){a0=b2[b1]
if(a0.b!=null){b5=a0.a
b6=a0.b
b6.toString
J.x(f,b5,b6)}}b2=i.b
b3=B.bS.k(0,h)
b3.toString
b2.a.i(0,b3,a8.a(f))}catch(b4){continue}}}c2.b=null
b7=a2.k(0,"ifd1")
if(b7!=null){a2=b7.a
a2=a2.ae(513)&&a2.ae(514)}else a2=!1
if(a2){b8=b7.k(0,513).h(0)
b9=b7.k(0,514).h(0)
a2=t
if(typeof a2!=="number")return a2.b3()
c0=a2+b8
if(b9>0){a2=t
if(typeof a2!=="number")return A.hn(a2)
a2=c0>=a2&&c0+b9<=a4}else a2=!1
if(a2){c1=c5.d
c5.d=c0
c2.b=c5.ag(b9).a2()
c5.d=c1}}c5.e=c4
return!1},
ex(a,b){var t,s,r,q,p,o,n,m=a.m(),l=a.m(),k=a.l(),j=new A.hc(m,null)
if(l>=14)return j
t=B.bx[l]
s=k*B.t[l]
r=a.d
if((s>4?a.d=a.l()+b:r)+s>a.c)return j
q=a.ag(s)
switch(t.a){case 0:break
case 6:j.b=new A.by(new Int8Array(A.w(J.jL(B.e.gB(q.a2()),0,k))))
break
case 1:j.b=new A.bg(new Uint8Array(A.w(q.ag(k).a2())))
break
case 7:j.b=new A.cQ(new Uint8Array(A.w(q.ag(k).a2())))
break
case 2:j.b=new A.bZ(k===0?"":q.ah(k-1))
break
case 3:j.b=A.le(q,k)
break
case 4:j.b=A.l9(q,k)
break
case 5:j.b=A.la(q,k)
break
case 10:j.b=A.lc(q,k)
break
case 8:j.b=A.ld(q,k)
break
case 9:j.b=A.lb(q,k)
break
case 11:j.b=A.lf(q,k)
break
case 12:j.b=A.l8(q,k)
break
case 13:if(k===1){p=new A.cO(0)
o=q.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=o
o=$.a4()
if(0>=o.length)return A.a(o,0)
p.a=o[0]
j.b=p}break}a.d=r+4
return j}}
A.hc.prototype={}
A.f1.prototype={}
A.aK.prototype={
fJ(a){a.a.aT(0,new A.hJ(this))},
gaU(a){var t,s=this.a
if(s.a===0)return!0
for(s=new A.aq(s,s.r,s.e,A.l(s).v("aq<2>"));s.F();){t=s.d
if(!(t.a.a===0&&t.b.gaU(0)))return!1}return!0},
k(a,b){var t=this.a
if(!t.ae(b))t.i(0,b,new A.aC(A.D(u.p,u.r),new A.aK(A.D(u.N,u.P))))
t=t.k(0,b)
t.toString
return t}}
A.hJ.prototype={
$2(a,b){var t
A.b0(a)
t=A.l7(u.P.a(b))
this.a.a.i(0,a,t)
return t},
$S:13}
A.aC.prototype={
iZ(a){a.a.aT(0,new A.hK(this))
a.b.a.aT(0,new A.hL(this))},
k(a,b){var t=this.a.k(0,b)
return t},
i(a,b,c){this.a.i(0,b,c)},
gc3(){var t=this.a.k(0,274)
return t==null?null:t.h(0)},
sc3(a){this.a.bT(0,274)}}
A.hK.prototype={
$2(a,b){var t
A.u(a)
t=u.r.a(b).P()
this.a.a.i(0,a,t)
return t},
$S:22}
A.hL.prototype={
$2(a,b){var t
A.b0(a)
t=A.l7(u.P.a(b))
this.a.b.a.i(0,a,t)
return t},
$S:13}
A.ae.prototype={
ad(){return"IfdValueType."+this.b}}
A.a0.prototype={
a4(a,b){A.u(b)
return 0},
h(a){return this.a4(0,0)},
bg(){return new Uint8Array(0)},
D(a){return""},
S(a,b){var t=this
if(b==null)return!1
return b instanceof A.a0&&t.gav()===b.gav()&&t.gt(t)===b.gt(b)&&t.gH(t)===b.gH(b)},
gH(a){return 0},
bj(a){}}
A.bg.prototype={
P(){return new A.bg(new Uint8Array(A.w(this.a)))},
gav(){return B.aX},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.bg){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return this.a},
aG(a){a.aV(this.a)},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.bZ.prototype={
P(){return new A.bZ(this.a)},
gav(){return B.k},
gt(a){return this.a.length+1},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.bZ){t=this.a
s=b.a
t=t.length+1===s.length+1&&B.p.gH(t)===B.p.gH(s)}else t=!1
return t},
gH(a){return B.p.gH(this.a)},
bg(){return new Uint8Array(A.w(new A.aJ(this.a)))},
aG(a){a.aV(new A.aJ(this.a))
a.C(0)},
D(a){return this.a}}
A.c3.prototype={
fO(a,b){var t,s,r,q
for(t=this.a,s=t.$flags|0,r=0;r<b;++r){q=a.m()
s&2&&A.b(t)
if(!(r<t.length))return A.a(t,r)
t[r]=q}},
P(){return new A.c3(new Uint16Array(A.w(this.a)))},
gav(){return B.i},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.c3){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return J.ab(B.Y.gB(this.a))},
aG(a){var t,s=this.a,r=s.length
for(t=0;t<r;++t)a.aw(s[t])},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.aU.prototype={
fL(a,b){var t,s,r,q
for(t=this.a,s=t.$flags|0,r=0;r<b;++r){q=a.l()
s&2&&A.b(t)
if(!(r<t.length))return A.a(t,r)
t[r]=q}},
P(){return new A.aU(new Uint32Array(A.w(this.a)))},
gav(){return B.n},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.aU){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return J.ab(B.o.gB(this.a))},
aG(a){var t,s=this.a,r=s.length
for(t=0;t<r;++t)a.aF(s[t])},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.c_.prototype={
P(){return new A.c_(A.ls(this.a,u.k))},
gav(){return B.r},
gt(a){return this.a.length},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b].h(0)},
h(a){return this.a4(0,0)},
S(a,b){var t,s,r
if(b==null)return!1
if(b instanceof A.c_){t=this.a
s=t.length
r=b.a
t=s===r.length&&A.m(t)===A.m(r)}else t=!1
return t},
gH(a){return A.m(this.a)},
aG(a){var t,s,r,q
for(t=this.a,s=t.length,r=0;r<t.length;t.length===s||(0,A.a_)(t),++r){q=t[r]
a.aF(q.a)
a.aF(q.b)}},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=t[0].D(0)}else t=A.z(t)
return t}}
A.by.prototype={
P(){return new A.by(new Int8Array(A.w(this.a)))},
gav(){return B.b1},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.by){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return J.ab(B.aB.gB(this.a))},
aG(a){a.aV(J.V(B.aB.gB(this.a),0,null))},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.c2.prototype={
fN(a,b){var t,s,r,q,p
for(t=this.a,s=t.$flags|0,r=0;r<b;++r){q=a.m()
p=$.am()
p.$flags&2&&A.b(p)
p[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
q=q[0]
s&2&&A.b(t)
if(!(r<t.length))return A.a(t,r)
t[r]=q}},
P(){return new A.c2(new Int16Array(A.w(this.a)))},
gav(){return B.b2},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.c2){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return J.ab(B.aA.gB(this.a))},
aG(a){var t,s,r,q=new Int16Array(1),p=J.kP(B.aA.gB(q),0,null),o=this.a,n=o.length
for(t=p.length,s=0;s<n;++s){r=o[s]
if(0>=1)return A.a(q,0)
q[0]=r
if(0>=t)return A.a(p,0)
a.aw(p[0])}},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.c0.prototype={
fM(a,b){var t,s,r,q,p
for(t=this.a,s=t.$flags|0,r=0;r<b;++r){q=a.l()
p=$.K()
p.$flags&2&&A.b(p)
p[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
q=q[0]
s&2&&A.b(t)
if(!(r<t.length))return A.a(t,r)
t[r]=q}},
P(){return new A.c0(new Int32Array(A.w(this.a)))},
gav(){return B.b3},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.c0){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b]},
h(a){return this.a4(0,0)},
bj(a){var t=this.a
t.$flags&2&&A.b(t)
if(0>=t.length)return A.a(t,0)
t[0]=a},
bg(){return J.ab(B.X.gB(this.a))},
aG(a){var t,s,r,q=this.a,p=q.length
for(t=0;t<p;++t){s=q[t]
r=$.hq()
r.$flags&2&&A.b(r)
r[0]=s
s=$.jK()
if(0>=s.length)return A.a(s,0)
a.aF(s[0])}},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=""+t[0]}else t=A.z(t)
return t}}
A.c1.prototype={
P(){return new A.c1(A.ls(this.a,u.k))},
gav(){return B.aY},
gt(a){return this.a.length},
S(a,b){var t,s,r
if(b==null)return!1
if(b instanceof A.c1){t=this.a
s=t.length
r=b.a
t=s===r.length&&A.m(t)===A.m(r)}else t=!1
return t},
gH(a){return A.m(this.a)},
a4(a,b){var t
A.u(b)
t=this.a
if(!(b>=0&&b<t.length))return A.a(t,b)
return t[b].h(0)},
h(a){return this.a4(0,0)},
aG(a){var t,s,r,q,p,o
for(t=this.a,s=t.length,r=0;r<t.length;t.length===s||(0,A.a_)(t),++r){q=t[r]
p=$.hq()
p.$flags&2&&A.b(p)
p[0]=q.a
o=$.jK()
if(0>=o.length)return A.a(o,0)
a.aF(o[0])
p[0]=q.b
a.aF(o[0])}},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=t[0].D(0)}else t=A.z(t)
return t}}
A.cP.prototype={
fP(a,b){var t,s,r,q,p
for(t=this.a,s=t.$flags|0,r=0;r<b;++r){q=a.l()
p=$.K()
p.$flags&2&&A.b(p)
p[0]=q
q=$.bN()
if(0>=q.length)return A.a(q,0)
q=q[0]
s&2&&A.b(t)
if(!(r<t.length))return A.a(t,r)
t[r]=q}},
P(){return new A.cP(new Float32Array(A.w(this.a)))},
gav(){return B.aZ},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.cP){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
bg(){return J.ab(B.ai.gB(this.a))},
aG(a){var t,s=this.a,r=s.length
for(t=0;t<r;++t)a.jF(s[t])},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=A.z(t[0])}else t=A.z(t)
return t}}
A.cN.prototype={
fK(a,b){var t,s
for(t=this.a,s=0;s<b;++s)B.aj.i(t,s,a.d6())},
P(){return new A.cN(new Float64Array(A.w(this.a)))},
gav(){return B.b_},
gt(a){return this.a.length},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.cN){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
bg(){return J.ab(B.aj.gB(this.a))},
aG(a){var t,s=this.a,r=s.length
for(t=0;t<r;++t)a.jG(s[t])},
D(a){var t=this.a,s=t.length
if(s===1){if(0>=s)return A.a(t,0)
t=A.z(t[0])}else t=A.z(t)
return t}}
A.cQ.prototype={
P(){return new A.cQ(new Uint8Array(A.w(this.a)))},
gav(){return B.D},
gt(a){return this.a.length},
bg(){return this.a},
S(a,b){var t,s
if(b==null)return!1
if(b instanceof A.cQ){t=this.a
s=b.a
t=t.length===s.length&&A.m(t)===A.m(s)}else t=!1
return t},
gH(a){return A.m(this.a)},
aG(a){a.aV(this.a)},
D(a){return"<data>"}}
A.cO.prototype={
P(){return A.jU(this.a)},
gav(){return B.b0},
gt(a){return 1},
S(a,b){var t
if(b==null)return!1
t=!1
if(b instanceof A.cO)t=this.a===b.a
return t},
gH(a){return this.a},
a4(a,b){if(A.u(b)!==0)throw A.f(A.nI("Ifd tags must have exactly one entry (the offset)"))
return this.a},
h(a){return this.a4(0,0)},
bj(a){this.a=a},
bg(){var t=this.a
return new Uint8Array(A.w(A.j([B.a.j(t,24),B.a.j(t,16),B.a.j(t,8),t],u.t)))},
aG(a){a.aF(this.a)},
D(a){return"Ifd@"+this.a}}
A.ad.prototype={
ad(){return"BmpCompression."+this.b}}
A.ht.prototype={}
A.bc.prototype={
dU(a,b){var t,s,r,q,p,o,n,m=this,l=m.d,k=l<=40
if(k){t=m.r
t=t===B.an||t===B.ao}else t=!0
if(t){t=m.as=a.l()
s=A.jq(t)
m.CW=s
r=B.a.a0(t,s)
t=r>0
m.cx=t?255/r:0
s=m.at=a.l()
q=A.jq(s)
m.cy=q
p=B.a.a0(s,q)
m.db=t?255/p:0
s=m.ax=a.l()
q=A.jq(s)
m.dx=q
o=B.a.a0(s,q)
m.dy=t?255/o:0
if(!k||m.r===B.ao){k=m.ay=a.l()
t=A.jq(k)
m.fr=t
n=B.a.a0(k,t)
m.fx=n>0?255/n:0}else if(m.f===16){m.ay=4278190080
m.fr=24
m.fx=1}else{m.ay=4278190080
m.fr=24
m.fx=1}}else if(m.f===16){m.as=31744
m.CW=10
m.cx=8.225806451612904
m.at=992
m.cy=5
m.db=8.225806451612904
m.ax=31
m.dx=0
m.dy=8.225806451612904
m.fx=m.fr=m.ay=0}else{m.as=16711680
m.CW=16
m.cx=1
m.at=65280
m.cy=8
m.db=1
m.ax=255
m.dx=0
m.dy=1
m.ay=4278190080
m.fr=24
m.fx=1}k=a.d
a.d=k+(l-(k-m.fy))
if(m.f<=8)m.jq(a)},
gcq(){var t=this.d
if(t!==40)if(t===124){t=this.ay
t===$&&A.d()
t=t===0}else t=!1
else t=!0
return t},
gV(){return Math.abs(this.c)},
jq(a){var t,s,r,q,p,o=this,n=o.z
if(n===0)n=B.a.O(1,o.f)
o.ch=new A.aW(new Uint8Array(n*3),n,3)
for(t=0;t<n;++t){s=J.c(a.a,a.d++)
r=J.c(a.a,a.d++)
q=J.c(a.a,a.d++)
p=J.c(a.a,a.d++)
o.ch.cG(t,q,r,s,p)}},
j3(a,b){var t,s,r,q,p,o,n,m,l,k=this
u.dX.a(b)
if(k.ch!=null){t=k.f
if(t===1){s=a.G()
for(r=7;r>=0;--r)b.$4(B.a.bs(s,r)&1,0,0,0)
return}else if(t===2){s=a.G()
for(r=6;r>=0;r-=2)b.$4(B.a.bs(s,r)&2,0,0,0)}else if(t===4){s=a.G()
b.$4(B.a.j(s,4)&15,0,0,0)
b.$4(s&15,0,0,0)
return}else if(t===8){b.$4(a.G(),0,0,0)
return}}t=k.r
if(t===B.an&&k.f===32){q=a.l()
t=k.as
t===$&&A.d()
p=k.CW
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.cx
t===$&&A.d()
o=B.b.h(p*t)
t=k.at
t===$&&A.d()
p=k.cy
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.db
t===$&&A.d()
n=B.b.h(p*t)
t=k.ax
t===$&&A.d()
p=k.dx
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.dy
t===$&&A.d()
m=B.b.h(p*t)
if(k.gcq())l=255
else{t=k.ay
t===$&&A.d()
p=k.fr
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.fx
t===$&&A.d()
l=B.b.h(p*t)}return b.$4(o,n,m,l)}else{p=k.f
if(p===32&&t===B.aL){m=a.G()
n=a.G()
o=a.G()
l=a.G()
return b.$4(o,n,m,k.gcq()?255:l)}else if(p===24){m=a.G()
n=a.G()
return b.$4(a.G(),n,m,255)}else if(p===16){q=a.m()
t=k.as
t===$&&A.d()
p=k.CW
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.cx
t===$&&A.d()
o=B.b.h(p*t)
t=k.at
t===$&&A.d()
p=k.cy
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.db
t===$&&A.d()
n=B.b.h(p*t)
t=k.ax
t===$&&A.d()
p=k.dx
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.dy
t===$&&A.d()
m=B.b.h(p*t)
if(k.gcq())l=255
else{t=k.ay
t===$&&A.d()
p=k.fr
p===$&&A.d()
p=B.a.a0((q&t)>>>0,p)
t=k.fx
t===$&&A.d()
l=B.b.h(p*t)}return b.$4(o,n,m,l)}else throw A.f(A.n("Unsupported bitsPerPixel ("+p+") or compression ("+t.D(0)+")."))}},
$iJ:1}
A.eR.prototype={
bm(a){var t,s
if(!A.kU(A.v(a,!1,null,0))||a.length<18)return!1
t=A.v(a,!1,null,0)
t.d+=14
s=t.l()
return s>=12&&s<=124},
aP(a){var t
if(!this.bm(a))return null
t=A.v(a,!1,null,0)
this.a=t
return this.b=A.mS(t,null)},
al(a0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=null,a=c.b
if(a==null)return new A.bh(b,b,b,b,0,B.j,0,0)
t=c.a
t===$&&A.d()
s=a.a.b
s===$&&A.d()
t.d=s
r=a.f
s=a.b
q=B.a.Y(s*r+31,32)*4
t=c.c
if(t)p=4
else if(r===1||r===4||r===8)p=1
else{o=r===32?4:3
p=o}if(t)n=B.f
else if(r===1)n=B.w
else{if(r===2)o=B.y
else if(r===4)o=B.z
else o=B.f
n=o}m=t?b:a.ch
l=A.R(b,b,n,0,B.j,a.gV(),b,0,p,m,B.f,s,!1)
for(k=l.gV()-1,t=a.c,s=1/t<0,o=t<0,t=t===0;k>=0;--k){j={}
if(!(t?s:o))i=k
else{h=l.a
h=h==null?b:h.b
i=(h==null?0:h)-1-k}h=c.a
g=h.ai(q)
h.d=h.d+(g.c-g.d)
h=l.a
f=h==null
e=f?b:h.a
if(e==null)e=0
j.a=0
d=f?b:h.L(0,i,b)
if(d==null)d=new A.G()
while(j.a<e)a.j3(g,new A.hs(j,c,e,a,d))}return l},
aS(a,b){if(this.aP(a)==null)return null
return this.al(0)}}
A.hs.prototype={
$4(a,b,c,d){var t,s,r=this,q=r.a
if(q.a<r.c){t=r.b.c&&r.d.ch!=null
s=r.e
if(t){t=r.d
s.a8(t.ch.aO(a),t.ch.aN(a),t.ch.aM(a),t.ch.aX(a))}else s.a8(a,b,c,d)
s.F();++q.a}},
$S:37}
A.hw.prototype={}
A.J.prototype={}
A.hv.prototype={}
A.hx.prototype={}
A.f2.prototype={}
A.dI.prototype={
ct(){return this.w},
bh(a,b,c,d,e){throw A.f(A.n("B44 compression not yet supported."))},
ca(a,b,c){return this.bh(a,b,c,null,null)},
D(a){return A.z(this.r)+" "+this.x}}
A.cL.prototype={
ad(){return"ExrChannelType."+this.b}}
A.bV.prototype={
ad(){return"ExrChannelName."+this.b}}
A.f3.prototype={
fE(a){var t=this,s=a.cv()
t.a=s
if(s.length===0)return
s=a.l()
if(!(s<3))return A.a(B.bo,s)
t.c=B.bo[s]
a.G()
a.d+=3
t.f=a.l()
t.r=a.l()
s=t.a
if(s==="R"){t.w=!0
t.b=B.cD}else if(s==="G"){t.w=!0
t.b=B.cE}else if(s==="B"){t.w=!0
t.b=B.cF}else if(s==="A"){t.w=!0
t.b=B.cG}else{t.w=!1
t.b=B.cH}switch(t.c.a){case 0:t.d=4
break
case 1:t.d=2
break
case 2:t.d=4
break}}}
A.aT.prototype={
ad(){return"ExrCompressorType."+this.b}}
A.be.prototype={
bh(a,b,c,d,e){throw A.f(A.n("Unsupported compression type"))},
ca(a,b,c){return this.bh(a,b,c,null,null)}}
A.fl.prototype={}
A.f4.prototype={
sf9(a){this.c=u.T.a(a)}}
A.f5.prototype={
fF(a){var t,s,r,q,p=this,o=A.v(a,!1,null,0)
if(o.l()!==20000630)throw A.f(A.n("File is not an OpenEXR image file."))
t=p.d=o.G()
if(t!==2)throw A.f(A.n("Cannot read version "+t+" image files."))
t=p.e=o.bf()
if((t&4294967289)>>>0!==0)throw A.f(A.n("The file format version number's flag field contains unrecognized flags."))
if((t&16)===0){s=p.c
r=A.lh(s.length,(t&2)!==0,o)
if(r.w>0)B.c.A(s,r)}else for(t=p.c;;){r=A.lh(t.length,(p.e&2)!==0,o)
if(r.w<=0)break
B.c.A(t,r)}t=p.c
s=t.length
if(s===0)throw A.f(A.n("Error reading image header"))
for(q=0;q<t.length;t.length===s||(0,A.a_)(t),++q)t[q].jp(o)
p.iy(o)},
iy(a){var t,s,r,q,p=this
for(t=p.c,s=t.length,r=0;r<t.length;t.length===s||(0,A.a_)(t),++r){q=t[r]
p.a=Math.max(p.a,q.w)
p.b=Math.max(p.b,q.x)
if(q.db)p.iH(q,a)
else p.iG(q,a)}},
iH(b5,b6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3=null,b4=this.e
b4===$&&A.d()
t=(b4&16)!==0
b4=b5.b
b4.toString
s=b5.CW
r=b5.ay
q=A.o(b6,b3,0)
p=b5.c
o=b5.a
n=0
m=0
for(;;){l=b5.k1
l.toString
if(!(n<l))break
k=0
for(;;){l=b5.id
l.toString
if(!(k<l))break
l=m!==0
j=0
i=0
for(;;){h=b5.go
if(!(n<h.length))return A.a(h,n)
if(!(j<h[n]))break
g=0
for(;;){h=b5.fy
if(!(k<h.length))return A.a(h,k)
if(!(g<h[k]))break
if(l)break
if(!(m>=0&&m<r.length))return A.a(r,m)
h=r[m]
if(!(i>=0&&i<h.length))return A.a(h,i)
q.d=h[i]
if(t)if(q.l()!==o)throw A.f(A.n("Invalid Image Data"))
f=q.l()
e=q.l()
q.l()
q.l()
d=q.ai(q.l())
q.d=q.d+(d.c-d.d)
h=b5.dy
h.toString
c=e*h
b=b5.dx
b.toString
h=s.bh(d,f*b,c,b,h)
b=h.length
b=Math.min(b,b)
a=new A.aa(h,0,b,0,!1)
a0=s.a
a1=s.b
a2=p.length
a3=0
a4=0
for(;;){if(!(a4<a1&&c<this.b))break
for(a5=0;a5<a2;++a5){if(a3>=b)break
if(!(a5<p.length))return A.a(p,a5)
a6=p[a5]
h=b5.dx
h.toString
a7=f*h
for(a8=0;a8<a0;++a8,++a7){h=a6.c
h===$&&A.d()
switch(h.a){case 1:h=a.m()
a9=$.N
a9=a9!=null?a9:A.U()
if(!(h<a9.length))return A.a(a9,h)
b0=a9[h]
break
case 2:b0=a.m()
break
case 0:b0=a.l()
break
default:b0=b3}h=a6.d
h===$&&A.d()
a3+=h
h=a6.w
h===$&&A.d()
if(h){h=b4.a
b1=h==null?b3:h.L(a7,c,b3)
if(b1==null)b1=new A.G()
h=a6.b
h===$&&A.d()
b1.i(0,h.a,b0)}else{h=a6.a
h===$&&A.d()
a9=b4.b
b2=a9!=null?a9.k(0,h):b3
if(b2!=null)b2.a3(a7,c,b0,0,0)}}}++a4;++c}++g;++i}++j}++k;++m}++n}},
iG(a7,a8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5=null,a6=this.e
a6===$&&A.d()
t=(a6&16)!==0
a6=a7.b
a6.toString
s=a7.CW
r=a7.ay
if(0>=r.length)return A.a(r,0)
q=r[0]
p=a7.cx
o=A.o(a8,a5,0)
for(r=q.length,n=a7.c,m=s!=null,l=0,k=0;k<r;++k){o.d=q[k]
if(t)if(o.l()!==3.141592653589793)throw A.f(A.n("Invalid Image Data"))
j=o.l()
i=$.K()
i.$flags&2&&A.b(i)
i[0]=j
j=$.a4()
if(0>=j.length)return A.a(j,0)
i[0]=o.l()
h=o.ai(j[0])
o.d=o.d+(h.c-h.d)
if(m){j=s.ca(h,0,l)
i=j.length
g=new A.aa(j,0,Math.min(i,i),0,!1)}else g=h
f=g.c-g.d
e=n.length
d=0
for(;;){if(!(d<p&&l<this.b))break
j=a7.cy
if(!(l>=0&&l<j.length))return A.a(j,l)
c=j[l]
if(c>=f)break
for(b=0;b<e;++b){if(c>=f)break
if(!(b<n.length))return A.a(n,b)
a=n[b]
a0=a7.w
for(a1=0;a1<a0;++a1){j=a.c
j===$&&A.d()
switch(j.a){case 1:j=g.m()
i=$.N
i=i!=null?i:A.U()
if(!(j<i.length))return A.a(i,j)
a2=i[j]
break
case 2:a2=g.m()
break
case 0:a2=g.l()
break
default:a2=a5}j=a.d
j===$&&A.d()
c+=j
j=a.w
j===$&&A.d()
if(j){j=a6.a
a3=j==null?a5:j.L(a1,l,a5)
if(a3==null)a3=new A.G()
j=a.b
j===$&&A.d()
a3.i(0,j.a,a2)}else{j=a.a
j===$&&A.d()
i=a6.b
a4=i!=null?i.k(0,j):a5
if(a4!=null)a4.a3(a1,l,a2,0,0)}}}++d;++l}}},
$iJ:1}
A.dt.prototype={
fG(a5,a6,a7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2=this,a3=null,a4=A.D(u.N,u.v)
for(t=a2.e,s=u.t,r=u.L,q=a2.c,p=B.C;;){o=a7.cv()
if(o.length===0)break
a7.cv()
n=a7.ai(a7.l())
a7.d=a7.d+(n.c-n.d)
t.i(0,o,new A.f2())
switch(o){case"channels":for(;;){m=new A.f3()
m.fE(n)
l=m.a
l===$&&A.d()
if(l.length===0)break
k=m.w
k===$&&A.d()
if(k){++a2.d
l=m.c
l===$&&A.d()
if(l===B.aq)p=B.C
else p=l===B.ar?B.H:B.I}else{k=m.c
k===$&&A.d()
if(k===B.aq){k=a2.w
j=a2.x
a4.i(0,l,new A.cR(new Uint16Array(k*j),k,j,1))}else if(k===B.ar){k=a2.w
j=a2.x
a4.i(0,l,new A.cS(new Float32Array(k*j),k,j,1))}else if(k===B.aS){k=a2.w
j=a2.x
a4.i(0,l,new A.cW(new Uint32Array(k*j),k,j,1))}}B.c.A(q,m)}break
case"chromaticities":l=new Float32Array(8)
a2.at=l
k=n.l()
j=$.K()
j.$flags&2&&A.b(j)
j[0]=k
k=$.bN()
if(0>=k.length)return A.a(k,0)
l[0]=k[0]
l=a2.at
j[0]=n.l()
i=k[0]
l.$flags&2&&A.b(l)
l[1]=i
i=a2.at
j[0]=n.l()
l=k[0]
i.$flags&2&&A.b(i)
i[2]=l
l=a2.at
j[0]=n.l()
i=k[0]
l.$flags&2&&A.b(l)
l[3]=i
i=a2.at
j[0]=n.l()
l=k[0]
i.$flags&2&&A.b(i)
i[4]=l
l=a2.at
j[0]=n.l()
i=k[0]
l.$flags&2&&A.b(l)
l[5]=i
i=a2.at
j[0]=n.l()
l=k[0]
i.$flags&2&&A.b(i)
i[6]=l
l=a2.at
j[0]=n.l()
k=k[0]
l.$flags&2&&A.b(l)
l[7]=k
break
case"compression":l=J.c(n.a,n.d++)
if(!(l>=0&&l<8))return A.a(B.by,l)
a2.ax=B.by[l]
break
case"dataWindow":l=n.l()
k=$.K()
k.$flags&2&&A.b(k)
k[0]=l
l=$.a4()
if(0>=l.length)return A.a(l,0)
j=l[0]
k[0]=n.l()
i=l[0]
k[0]=n.l()
h=l[0]
k[0]=n.l()
l=r.a(A.j([j,i,h,l[0]],s))
a2.r=l
a2.w=l[2]-l[0]+1
a2.x=l[3]-l[1]+1
break
case"displayWindow":l=n.l()
k=$.K()
k.$flags&2&&A.b(k)
k[0]=l
l=$.a4()
if(0>=l.length)return A.a(l,0)
k[0]=n.l()
k[0]=n.l()
k[0]=n.l()
break
case"lineOrder":break
case"pixelAspectRatio":l=n.l()
k=$.K()
k.$flags&2&&A.b(k)
k[0]=l
l=$.bN()
if(0>=l.length)return A.a(l,0)
break
case"screenWindowCenter":l=n.l()
k=$.K()
k.$flags&2&&A.b(k)
k[0]=l
l=$.bN()
if(0>=l.length)return A.a(l,0)
k[0]=n.l()
break
case"screenWindowWidth":l=n.l()
k=$.K()
k.$flags&2&&A.b(k)
k[0]=l
l=$.bN()
if(0>=l.length)return A.a(l,0)
break
case"tiles":a2.dx=n.l()
a2.dy=n.l()
g=J.c(n.a,n.d++)
a2.fr=g&15
a2.fx=B.a.j(g,4)&15
break
case"type":f=n.cv()
if(f!=="deepscanline")if(f!=="deeptile")throw A.f(A.n("EXR Invalid type: "+f))
break
default:break}}t=a2.w
a2.b=A.R(a3,a3,p,0,B.j,a2.x,a3,0,a2.d,a3,B.f,t,!1)
for(t=new A.O(a4,a4.r,a4.e,a4.$ti.v("O<1>"));t.F();){s=t.d
r=a2.b
r.toString
l=a4.k(0,s)
l.toString
r.fq(s,l)}if(a2.db){t={}
s=a2.r
s===$&&A.d()
a2.id=a2.h5(s[0],s[2],s[1],s[3])
s=a2.r
a2.k1=a2.h6(s[0],s[2],s[1],s[3])
if(a2.fr!==2)a2.k1=1
s=a2.id
s.toString
r=a2.r
a2.fy=a2.e2(s,r[0],r[2],a2.dx,a2.fx)
r=a2.k1
r.toString
s=a2.r
a2.go=a2.e2(r,s[1],s[3],a2.dy,a2.fx)
s=a2.h4()
a2.k2=s
r=a2.dx
r.toString
r=s*r
a2.k3=r
a2.CW=A.l0(a2.ax,a2,r,a2.dy)
t.a=t.b=0
r=a2.id
r.toString
s=a2.k1
s.toString
a2.ay=A.lt(r*s,new A.hz(t,a2),u.bv)}else{t=a2.x
s=a2.ch=new Uint32Array(t+1)
for(r=q.length,l=a2.r,k=a2.w,e=0;e<r;++e){d=q[e]
j=d.d
j===$&&A.d()
i=d.f
i===$&&A.d()
c=B.a.au(j*k,i)
for(j=d.r,b=0;b<t;++b){l===$&&A.d()
i=l[1]
j===$&&A.d()
if(B.a.a1(b+i,j)===0)s[b]=s[b]+c}}for(a=0,b=0;b<t;++b)a=Math.max(a,s[b])
t=A.l0(a2.ax,a2,a,a3)
a2.CW=t
t=a2.cx=t.ct()
s=a2.ch
r=s.length
q=new Uint32Array(r)
a2.cy=q
for(--r,a0=0,a1=0;a1<=r;++a1){if(B.a.a1(a1,t)===0)a0=0
q[a1]=a0
a0+=s[a1]}t=B.a.au(a2.x+t,t)
a2.ay=A.j([new Uint32Array(t-1)],u.hh)}},
h5(a,b,c,d){var t,s,r,q,p=this
switch(p.fr){case 0:t=1
break
case 1:s=Math.max(b-a+1,d-c+1)
r=p.fx
A.u(s)
t=(r===0?p.cR(s):p.cK(s))+1
break
case 2:q=b-a+1
t=(p.fx===0?p.cR(q):p.cK(q))+1
break
default:throw A.f(A.n("Unknown LevelMode format."))}return t},
h6(a,b,c,d){var t,s,r,q,p=this
switch(p.fr){case 0:t=1
break
case 1:s=Math.max(b-a+1,d-c+1)
r=p.fx
A.u(s)
t=(r===0?p.cR(s):p.cK(s))+1
break
case 2:q=d-c+1
t=(p.fx===0?p.cR(q):p.cK(q))+1
break
default:throw A.f(A.n("Unknown LevelMode format."))}return t},
cR(a){var t
for(t=0;a>1;){++t
a=B.a.j(a,1)}return t},
cK(a){var t,s
for(t=0,s=0;a>1;){if((a&1)!==0)s=1;++t
a=B.a.j(a,1)}return t+s},
h4(){var t,s,r,q,p
for(t=this.c,s=t.length,r=0,q=0;q<s;++q){p=t[q].d
p===$&&A.d()
r+=p}return r},
e2(a,b,c,d,e){var t,s,r,q,p,o,n=J.ag(a,u.p)
for(t=e===1,s=c-b+1,r=0;r<a;++r){q=B.a.O(1,r)
p=B.a.au(s,q)
if(t&&p*q<s)++p
o=Math.max(p,1)
d.toString
n[r]=B.a.au(o+d-1,d)}return n}}
A.hz.prototype={
$1(a){var t,s,r,q,p=this.b,o=p.fy,n=this.a,m=n.b
if(!(m<o.length))return A.a(o,m)
o=o[m]
t=p.go
s=n.a
if(!(s<t.length))return A.a(t,s)
t=t[s]
r=new Uint32Array(o*t)
q=m+1
n.b=q
if(q===p.id){n.b=0
n.a=s+1}return r},
$S:25}
A.fm.prototype={
jp(a){var t,s,r,q,p,o=this
if(o.db)for(t=0;t<o.ay.length;++t){s=0
for(;;){r=o.ay
if(!(t<r.length))return A.a(r,t)
r=r[t]
if(!(s<r.length))break
q=a.dL()
r.$flags&2&&A.b(r)
r[s]=q;++s}}else{r=o.ay
if(0>=r.length)return A.a(r,0)
p=r[0].length
for(t=0;t<p;++t){r=o.ay
if(0>=r.length)return A.a(r,0)
r=r[0]
q=a.dL()
r.$flags&2&&A.b(r)
if(!(t<r.length))return A.a(r,t)
r[t]=q}}}}
A.fn.prototype={
fS(a,b,c){var t,s,r,q=this,p=a.c.length,o=J.ag(p,u.eO)
for(t=0;t<p;++t)o[t]=new A.eH()
q.y=u.gR.a(o)
s=q.w
s.toString
r=B.a.Y(s*q.x,2)
q.z=new Uint16Array(r)},
ct(){return this.x},
bh(a5,a6,a7,a8,a9){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4=this
if(a8==null)a8=a4.c.w
if(a9==null)a9=a4.c.cx
t=a6+a8-1
s=a7+a9-1
r=a4.c
q=r.w
if(t>q)t=q-1
q=r.x
if(s>q)s=q-1
a4.a=t-a6+1
a4.b=s-a7+1
p=r.c
o=p.length
for(n=0,m=0;m<o;++m){l=p[m]
r=a4.y
r===$&&A.d()
if(!(m<r.length))return A.a(r,m)
k=r[m]
k.b=k.a=n
r=l.f
r===$&&A.d()
j=B.a.au(a6,r)
i=B.a.au(t,r)
r=j*r<a6?0:1
r=i-j+r
k.c=r
q=l.r
q===$&&A.d()
j=B.a.au(a7,q)
i=B.a.au(s,q)
h=j*q<a7?0:1
h=i-j+h
k.d=h
k.e=q
q=l.d
q===$&&A.d()
q=q/2|0
k.f=q
n+=r*h*q}g=a5.m()
f=a5.m()
if(f>=8192)throw A.f(A.n("Error in header for PIZ-compressed data (invalid bitmap size)."))
e=new Uint8Array(8192)
if(g<=f){d=a5.ag(f-g+1)
c=d.c-d.d
for(b=g,m=0;m<c;++m,b=a){a=b+1
r=J.c(d.a,d.d+m)
if(!(b<8192))return A.a(e,b)
e[b]=r}}a0=new Uint16Array(65536)
a1=a4.iL(e,a0)
A.n4(a5,a5.l(),a4.z,n)
for(m=0;m<o;++m){r=a4.y
r===$&&A.d()
if(!(m<r.length))return A.a(r,m)
k=r[m]
b=0
for(;;){r=k.f
r===$&&A.d()
if(!(b<r))break
q=a4.z
q.toString
h=k.a
h===$&&A.d()
a2=k.c
a2===$&&A.d()
a3=k.d
a3===$&&A.d()
A.n7(q,h+b,a2,r,a3,a2*r,a1);++b}}r=a4.z
r.toString
a4.h_(a0,r,n)
r=a4.r
if(r==null){r=a4.w
r.toString
r=a4.r=A.e3(!1,r*a4.x+73728)}r.a=0
for(;a7<=s;++a7)for(m=0;m<o;++m){r=a4.y
r===$&&A.d()
if(!(m<r.length))return A.a(r,m)
k=r[m]
r=k.e
r===$&&A.d()
if(B.a.a1(a7,r)!==0)continue
r=k.c
r===$&&A.d()
q=k.f
q===$&&A.d()
a6=r*q
for(;a6>0;--a6){r=a4.r
r.toString
q=a4.z
q.toString
h=k.b
h===$&&A.d()
k.b=h+1
if(!(h>=0&&h<q.length))return A.a(q,h)
r.aw(q[h])}}r=a4.r
return J.V(B.e.gB(r.c),0,r.a)},
ca(a,b,c){return this.bh(a,b,c,null,null)},
h_(a,b,c){var t,s,r,q=u.L
q.a(a)
q.a(b)
for(q=b.length,t=b.$flags|0,s=0;s<c;++s){if(!(s<q))return A.a(b,s)
r=b[s]
if(!(r>=0&&r<65536))return A.a(a,r)
r=a[r]
t&2&&A.b(b)
b[s]=r}},
iL(a,b){var t,s,r,q,p,o
for(t=b.$flags|0,s=0,r=0;r<65536;++r){if(r!==0){q=r>>>3
if(!(q<8192))return A.a(a,q)
q=(a[q]&1<<(r&7))>>>0!==0}else q=!0
if(q){p=s+1
t&2&&A.b(b)
if(!(s<65536))return A.a(b,s)
b[s]=r
s=p}}for(p=s;p<65536;p=o){o=p+1
t&2&&A.b(b)
if(!(p<65536))return A.a(b,p)
b[p]=0}return s-1}}
A.eH.prototype={}
A.fo.prototype={
ct(){return this.x},
bh(a3,a4,a5,a6,a7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=this,a1=B.B.bP(a3.a2()),a2=a0.y
if(a2==null){a2=a0.w
a2.toString
a2=a0.y=A.e3(!1,a0.x*a2)}a2.a=0
t=A.j([0,0,0,0],u.t)
s=new Uint32Array(1)
r=J.V(B.o.gB(s),0,null)
if(a6==null)a6=a0.c.w
if(a7==null)a7=a0.c.cx
q=a4+a6-1
p=a5+a7-1
a2=a0.c
o=a2.w
if(q>o)q=o-1
o=a2.x
if(p>o)p=o-1
a0.a=q-a4+1
a0.b=p-a5+1
a2=a2.c
n=a2.length
for(o=r.length,m=a1.length,l=a5,k=0;l<=p;++l)for(j=0;j<n;++j){if(!(j<a2.length))return A.a(a2,j)
i=a2[j]
h=i.r
h===$&&A.d()
if(B.a.a1(a5,h)!==0)continue
h=i.f
h===$&&A.d()
g=B.a.au(a4,h)
f=B.a.au(q,h)
h=g*h<a4?0:1
e=f-g+h
if(0>=1)return A.a(s,0)
s[0]=0
h=i.c
h===$&&A.d()
switch(h.a){case 0:B.c.i(t,0,k)
B.c.i(t,1,t[0]+e)
B.c.i(t,2,t[1]+e)
k=t[2]+e
for(d=0;d<e;++d){h=t[0]
B.c.i(t,0,h+1)
if(!(h>=0&&h<m))return A.a(a1,h)
h=a1[h]
c=t[1]
B.c.i(t,1,c+1)
if(!(c>=0&&c<m))return A.a(a1,c)
c=a1[c]
b=t[2]
B.c.i(t,2,b+1)
if(!(b>=0&&b<m))return A.a(a1,b)
b=a1[b]
s[0]=s[0]+((h<<24|c<<16|b<<8)>>>0)
for(a=0;a<4;++a){h=a0.y
h.toString
if(!(a<o))return A.a(r,a)
h.C(r[a])}}break
case 1:B.c.i(t,0,k)
B.c.i(t,1,t[0]+e)
k=t[1]+e
for(d=0;d<e;++d){h=t[0]
B.c.i(t,0,h+1)
if(!(h>=0&&h<m))return A.a(a1,h)
h=a1[h]
c=t[1]
B.c.i(t,1,c+1)
if(!(c>=0&&c<m))return A.a(a1,c)
c=a1[c]
s[0]=s[0]+((h<<8|c)>>>0)
for(a=0;a<2;++a){h=a0.y
h.toString
if(!(a<o))return A.a(r,a)
h.C(r[a])}}break
case 2:B.c.i(t,0,k)
B.c.i(t,1,t[0]+e)
B.c.i(t,2,t[1]+e)
k=t[2]+e
for(d=0;d<e;++d){h=t[0]
B.c.i(t,0,h+1)
if(!(h>=0&&h<m))return A.a(a1,h)
h=a1[h]
c=t[1]
B.c.i(t,1,c+1)
if(!(c>=0&&c<m))return A.a(a1,c)
c=a1[c]
b=t[2]
B.c.i(t,2,b+1)
if(!(b>=0&&b<m))return A.a(a1,b)
b=a1[b]
s[0]=s[0]+((h<<24|c<<16|b<<8)>>>0)
for(a=0;a<4;++a){h=a0.y
h.toString
if(!(a<o))return A.a(r,a)
h.C(r[a])}}break}}a2=a0.y
return J.V(B.e.gB(a2.c),0,a2.a)},
ca(a,b,c){return this.bh(a,b,c,null,null)}}
A.fp.prototype={
ct(){return 1},
bh(a,a0,a1,a2,a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=this,c=a.c,b=A.e3(!1,(c-a.d)*2)
if(a2==null)a2=d.c.w
if(a3==null)a3=d.c.cx
t=a0+a2-1
s=a1+a3-1
r=d.c
q=r.w
if(t>q)t=q-1
r=r.x
if(s>r)s=r-1
d.a=t-a0+1
d.b=s-a1+1
while(r=a.d,r<c){q=a.a
a.d=r+1
r=J.c(q,r)
q=$.an()
q.$flags&2&&A.b(q)
q[0]=r
r=$.av()
if(0>=r.length)return A.a(r,0)
p=r[0]
if(p<0){o=-p
for(;n=o-1,o>0;o=n)b.C(J.c(a.a,a.d++))}else for(o=p;n=o-1,o>=0;o=n)b.C(J.c(a.a,a.d++))}m=J.V(B.e.gB(b.c),0,b.a)
l=m.length
for(c=m.$flags|0,k=1;k<l;++k){r=m[k-1]
q=m[k]
c&2&&A.b(m)
m[k]=r+q-128}c=d.r
if(c==null||c.length!==l)c=d.r=new Uint8Array(l)
r=B.a.Y(l+1,2)
for(j=0,i=0;;r=e,j=g){if(i<l){h=i+1
g=j+1
if(!(j<l))return A.a(m,j)
q=m[j]
c.$flags&2&&A.b(c)
f=c.length
if(!(i<f))return A.a(c,i)
c[i]=q}else break
if(h<l){i=h+1
e=r+1
if(!(r<l))return A.a(m,r)
r=m[r]
if(!(h<f))return A.a(c,h)
c[h]=r}else break}return c},
ca(a,b,c){return this.bh(a,b,c,null,null)},
D(a){return A.z(this.w)}}
A.dJ.prototype={
ct(){return this.x},
bh(a,b,c,d,e){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=this,f=B.B.bP(a.a2())
if(d==null)d=g.c.w
if(e==null)e=g.c.cx
t=b+d-1
s=c+e-1
r=g.c
q=r.w
if(t>q)t=q-1
r=r.x
if(s>r)s=r-1
g.a=t-b+1
g.b=s-c+1
p=f.length
for(r=f.$flags|0,o=1;o<p;++o){q=f[o-1]
n=f[o]
r&2&&A.b(f)
f[o]=q+n-128}r=g.y
if(r==null||r.length!==p)r=g.y=new Uint8Array(p)
q=B.a.Y(p+1,2)
for(m=0,l=0;;q=h,m=j){if(l<p){k=l+1
j=m+1
if(!(m<p))return A.a(f,m)
n=f[m]
r.$flags&2&&A.b(r)
i=r.length
if(!(l<i))return A.a(r,l)
r[l]=n}else break
if(k<p){l=k+1
h=q+1
if(!(q<p))return A.a(f,q)
q=f[q]
if(!(k<i))return A.a(r,k)
r[k]=q}else break}return r},
ca(a,b,c){return this.bh(a,b,c,null,null)},
D(a){return A.z(this.w)}}
A.hy.prototype={
al(a){var t=this.a
if(t==null)return null
t=t.c
if(!(a<t.length))return A.a(t,a)
return t[a].b},
aS(a,b){var t=new A.f5(A.j([],u.dw))
t.fF(a)
this.a=t
return this.al(0)}}
A.dw.prototype={
jc(a,b,c,d){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=this
if(d===0&&f.c!=null){t=f.c
t.toString
return t}for(t=f.b,s=f.d,r=-1,q=-1,p=0;p<t;++p){o=s.aO(p)
n=s.aN(p)
m=s.aM(p)
l=s.aX(p)
if(o===a&&n===b&&m===c&&l===d)return p
k=a-o
j=b-n
i=c-m
h=d-l
g=k*k+j*j+i*i+h*h
if(q===-1){q=p
r=g}else if(g<r){q=p
r=g}}return q},
dM(){var t,s,r,q,p,o,n,m=this
if(m.c==null)return m.d
t=m.d
s=t.a
r=new A.aW(new Uint8Array(s*4),s,4)
for(q=0;q<s;++q){p=t.aO(q)
o=t.aN(q)
n=t.aM(q)
r.cG(q,p,o,n,q===m.c?0:255)}return r}}
A.dx.prototype={
fH(a){var t,s,r,q,p,o,n=this
n.a=a.m()
n.b=a.m()
n.c=a.m()
n.d=a.m()
t=a.G()
n.e=(t&64)!==0
if((t&128)!==0){n.f=A.l4(B.a.O(1,(t&7)+1))
for(s=0;r=n.f,s<r.b;++s){q=J.c(a.a,a.d++)
p=J.c(a.a,a.d++)
o=J.c(a.a,a.d++)
r.d.b5(s,q,p,o)}}n.y=a.d-a.b}}
A.fq.prototype={}
A.dy.prototype={$iJ:1}
A.hE.prototype={
aP(a){var t,s,r,q,p,o,n,m,l,k,j=this
j.f=A.v(a,!1,null,0)
j.a=new A.dy(A.j([],u.w))
if(!j.eh())return null
try{while(q=j.f,p=q.d,p<q.c){o=q.a
q.d=p+1
t=J.c(o,p)
switch(t){case 44:s=j.eD()
if(s==null){q=j.a
return q}q=s
q.r=j.e
q.w=j.c
if(j.b!==0){if(s.f==null&&j.a.e!=null){q=j.a.e
p=q.a
o=q.b
n=q.c
q=q.d
s.f=new A.dw(p,o,n,new A.aW(new Uint8Array(A.w(q.c)),q.a,q.b))}if(s.f!=null)s.f.c=j.d}B.c.A(j.a.r,s)
break
case 33:q=j.f
r=J.c(q.a,q.d++)
if(J.bO(r,255)){q=j.f
if(q.ah(J.c(q.a,q.d++))==="NETSCAPE2.0"){m=J.c(q.a,q.d++)
l=J.c(q.a,q.d++)
if(m===3&&l===1)j.r=q.m()}else j.cY()}else if(J.bO(r,249)){q=j.f
q.toString
j.it(q)}else j.cY()
break
case 59:q=j.a
return q
default:break}}}catch(k){}return j.a},
it(a){var t,s,r,q=this
a.G()
t=a.G()
q.e=a.m()
q.d=a.G()
a.G()
q.c=B.a.j(t,2)&7
q.b=t&1
s=a.cH(1,0)
if(J.c(s.a,s.d)===44){++a.d
r=q.eD()
if(r==null)return
r.r=q.e
r.w=q.c
s=q.b!==0
r.x=s?q.d:-1
if(s){s=r.f
if(s==null&&q.a.e!=null){s=q.a.e
s.toString
s=r.f=A.nc(s)}if(s!=null)s.c=q.d}B.c.A(q.a.r,r)}},
al(a){var t,s,r,q=this,p=q.f
if(p==null||q.a==null)return null
t=q.a.r
s=t.length
if(a>=s)return null
r=t[a]
t=r.y
t===$&&A.d()
p.d=t
return q.hp(r)},
aS(a6,a7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4=this,a5=null
if(a4.aP(a6)==null)return a5
t=a4.a.r.length
if(t===1)return a4.al(0)
for(t=u.p,s=a5,r=s,q=0;p=a4.a.r,q<p.length;++q){a7=p[q]
o=a4.al(q)
if(o==null)return a5
o.y=a7.r*10
if(r==null||s==null){o.r=a4.r
s=o
r=s
continue}p=o.a
n=p==null
m=n?a5:p.a
if(m==null)m=0
l=s.a
k=l==null
j=k?a5:l.a
i=!1
if(m===(j==null?0:j)){p=n?a5:p.b
if(p==null)p=0
n=k?a5:l.b
if(p===(n==null?0:n)){p=a7.a
p===$&&A.d()
if(p===0){p=a7.b
p===$&&A.d()
p=p===0&&a7.w===2}else p=i}else p=i}else p=i
if(p){r.aZ(o)
s=o
continue}h=a7.f
if(!(h!=null)){p=a4.a.e
p.toString
h=p}p=k?a5:l.a
if(p==null)p=0
n=k?a5:l.b
if(n==null)n=0
g=A.R(a5,a5,B.f,0,B.j,n,a5,0,1,h.dM(),B.f,p,!1)
p=a7.w
if(p===2){p=g.a
f=p==null?a5:J.ab(p.gB(p))
if(f==null){p=g.a
p=p==null?a5:p.gB(p)
if(p==null)p=B.e.gB(new Uint8Array(0))
f=J.ab(p)}p=a7.x
n=f.length-1
if(p!==-1)B.e.aB(f,0,n,p)
else{p=a4.a.c.a
m=p.length
if(m!==0){if(0>=m)return A.a(p,0)
p=p[0]}else p=0
B.e.aB(f,0,n,p)}}else if(p!==3)if(a7.f!=null){p=s.a
e=p==null?a5:p.gR()
d=A.D(t,t)
for(p=e.a,c=0;c<p;++c)d.i(0,c,h.jc(e.aO(c),e.aN(c),e.aM(c),e.aX(c)))
p=g.a
b=p==null?a5:J.ab(p.gB(p))
if(b==null){p=g.a
p=p==null?a5:p.gB(p)
if(p==null)p=B.e.gB(new Uint8Array(0))
b=J.ab(p)}p=s.a
a=p==null?a5:J.ab(p.gB(p))
if(a==null){p=s.a
p=p==null?a5:p.gB(p)
if(p==null)p=B.e.gB(new Uint8Array(0))
a=J.ab(p)}for(a0=b.length,p=a.length,n=b.$flags|0,a1=0;a1<a0;++a1){if(!(a1<p))return A.a(a,a1)
a2=d.k(0,a[a1])
if(a2!=null&&a2!==-1){n&2&&A.b(b)
b[a1]=a2}}}g.y=o.y
for(p=o.a,p=p.gI(p);p.F();){a3=p.gM()
if(a3.gu()!==0){n=a3.gaL()
m=a7.a
m===$&&A.d()
l=a3.gaH()
k=a7.b
k===$&&A.d()
g.bI(n+m,l+k,a3)}}r.aZ(g)
s=g}return r},
eD(){var t,s=this.f
if(s.d>=s.c)return null
t=new A.fq()
t.fH(s);++this.f.d
this.cY()
return t},
hp(a){var t,s,r,q,p,o,n,m,l,k,j=this,i=null
if(j.w==null){j.w=new Uint8Array(256)
j.x=new Uint8Array(4095)
j.y=new Uint8Array(4096)
j.z=new Uint32Array(4096)}t=j.Q=j.f.G()
s=B.a.W(1,t)
j.dy=s;++s
j.dx=s
j.db=s+1;++t
j.cy=t
j.cx=B.a.W(1,t)
j.ay=0
j.CW=4098
j.at=j.ax=0
t=j.w
t.toString
t.$flags&2&&A.b(t)
t[0]=0
t=j.z
t.toString
B.o.aB(t,0,4096,4098)
t=a.c
t===$&&A.d()
s=a.d
s===$&&A.d()
r=a.a
r===$&&A.d()
q=j.a
if(r+t<=q.a){r=a.b
r===$&&A.d()
r=r+s>q.b}else r=!0
if(r)return i
p=a.f
if(!(p!=null)){r=q.e
r.toString
p=r}j.as=t*s
o=A.R(i,i,B.f,0,B.j,s,i,0,1,p.dM(),B.f,t,!1)
n=new Uint8Array(t)
t=a.e
t===$&&A.d()
if(t){t=a.b
t===$&&A.d()
for(s=t+s,m=0,l=0;m<4;++m)for(k=t+B.di[m];k<s;k+=B.eC[m],++l){if(!j.ei(n))return o
j.eH(o,k,p,n)}}else for(k=0;k<s;++k){if(!j.ei(n))return o
j.eH(o,k,p,n)}return o},
eH(a,b,c,d){var t,s,r,q=d.length
for(t=0;t<q;++t){s=d[t]
r=a.a
if(r!=null)r.a3(t,b,s,0,0)}},
eh(){var t,s,r,q,p,o=this,n=o.f.ah(6)
if(n!=="GIF87a"&&n!=="GIF89a")return!1
t=o.a
t.toString
t.a=o.f.m()
t=o.a
t.toString
t.b=o.f.m()
s=o.f.G()
t=o.a
t.toString
t.c=new A.aS(new Uint8Array(A.w(A.j([o.f.G()],u.t))));++o.f.d
if((s&128)!==0){t=o.a
t.toString
t.e=A.l4(B.a.O(1,(s&7)+1))
for(r=0;r<o.a.e.b;++r){t=o.f
q=J.c(t.a,t.d++)
t=o.f
p=J.c(t.a,t.d++)
t=o.f
s=J.c(t.a,t.d++)
o.a.e.d.b5(r,q,p,s)}}o.a.toString
return!0},
ei(a){var t=this,s=t.as
s.toString
t.as=s-a.length
if(!t.hA(a))return!1
if(t.as===0)t.cY()
return!0},
cY(){var t,s,r,q=this.f
if(q.d>=q.c)return!0
t=q.G()
for(;;){if(t!==0){q=this.f
q=q.d<q.c}else q=!1
if(!q)break
q=this.f
s=q.d+=t
if(s>=q.c)return!0
r=q.a
q.d=s+1
t=J.c(r,s)}return!0},
hA(a){var t,s,r,q,p,o,n,m,l,k,j,i,h=this,g=h.ay
if(g>4095)return!1
t=a.length
s=0
if(g!==0){r=a.$flags|0
for(;;){if(!(g!==0&&s<t))break
q=s+1
p=h.x
p===$&&A.d()
g=h.ay=g-1
if(!(g>=0))return A.a(p,g)
p=p[g]
r&2&&A.b(a)
if(!(s<t))return A.a(a,s)
a[s]=p
s=q}}for(g=a.$flags|0;s<t;){o=h.ch=h.hz()
if(o==null)return!1
r=h.dx
if(o===r)return!1
p=h.dy
if(o===p){for(p=h.z,n=0;n<=4095;++n){p.toString
p.$flags&2&&A.b(p)
p[n]=4098}h.db=r+1
r=h.Q+1
h.cy=r
h.cx=B.a.W(1,r)
h.CW=4098}else{if(o<p){q=s+1
g&2&&A.b(a)
if(!(s>=0))return A.a(a,s)
a[s]=o
s=q}else{r=h.z
r.toString
if(o>>>0!==o||o>=4096)return A.a(r,o)
if(r[o]===4098){m=h.db-2
if(o===m){o=h.CW
l=h.y
l===$&&A.d()
k=h.x
k===$&&A.d()
j=h.ay++
p=h.dr(r,o,p)
k.$flags&2&&A.b(k)
if(!(j>=0&&j<4095))return A.a(k,j)
k[j]=p
l.$flags&2&&A.b(l)
if(!(m>=0&&m<4096))return A.a(l,m)
l[m]=p}else return!1}n=0
for(;;){i=n+1
if(!(n<=4095&&o>h.dy&&o<=4095))break
r=h.x
r===$&&A.d()
p=h.ay++
m=h.y
m===$&&A.d()
if(!(o>=0&&o<4096))return A.a(m,o)
m=m[o]
r.$flags&2&&A.b(r)
if(!(p>=0&&p<4095))return A.a(r,p)
r[p]=m
o=h.z[o]
n=i}if(i>=4095||o>4095)return!1
r=h.x
r===$&&A.d()
p=h.ay
m=h.ay=p+1
r.$flags&2&&A.b(r)
if(!(p>=0&&p<4095))return A.a(r,p)
r[p]=o
p=m
for(;;){if(!(p!==0&&s<t))break
q=s+1
p=h.ay=p-1
if(!(p>=0&&p<4095))return A.a(r,p)
m=r[p]
g&2&&A.b(a)
if(!(s>=0&&s<t))return A.a(a,s)
a[s]=m
s=q}}r=h.CW
if(r!==4098){p=h.z
p.toString
m=h.db-2
if(!(m>=0&&m<4096))return A.a(p,m)
m=p[m]===4098
p=m}else p=!1
if(p){p=h.z
p.toString
m=h.db-2
p.$flags&2&&A.b(p)
if(!(m>=0&&m<4096))return A.a(p,m)
p[m]=r
l=h.ch
k=h.y
j=h.dy
if(l===m){k===$&&A.d()
r=h.dr(p,r,j)
k.$flags&2&&A.b(k)
k[m]=r}else{k===$&&A.d()
l.toString
r=h.dr(p,l,j)
k.$flags&2&&A.b(k)
k[m]=r}}r=h.ch
r.toString
h.CW=r}}return!0},
hz(){var t,s,r,q,p=this
if(p.cy>12)return null
while(t=p.ax,s=p.cy,t<s){t=p.h1()
t.toString
s=p.at
r=p.ax
p.at=(s|B.a.W(t,r))>>>0
p.ax=r+8}r=p.at
if(!(s>=0&&s<13))return A.a(B.bh,s)
q=B.bh[s]
p.at=B.a.a_(r,s)
p.ax=t-s
t=p.db
if(t<4097){++t
p.db=t
t=t>p.cx&&s<12}else t=!1
if(t){p.cx=p.cx<<1>>>0
p.cy=s+1}return r&q},
dr(a,b,c){var t,s,r=0
for(;;){if(b>c){t=r+1
s=r<=4095
r=t}else s=!1
if(!s)break
if(b>4095)return 4098
a.toString
if(!(b>=0))return A.a(a,b)
b=a[b]}return b},
h1(){var t,s,r=this,q=r.w,p=q[0],o=q.$flags|0
if(p===0){p=r.f.G()
o&2&&A.b(q)
q[0]=p
q=r.w
p=q[0]
if(p===0)return null
B.e.bk(q,1,1+p,r.f.ag(p).a2())
q=r.w
t=q[1]
q.$flags&2&&A.b(q)
q[1]=2
q[0]=q[0]-1}else{s=q[1]
o&2&&A.b(q)
q[1]=s+1
if(!(s<256))return A.a(q,s)
t=q[s]
q[0]=p-1}return t}}
A.cM.prototype={
ad(){return"IcoType."+this.b}}
A.fe.prototype={$iJ:1}
A.ff.prototype={}
A.fd.prototype={
gV(){return B.a.Y(A.bc.prototype.gV.call(this),2)},
gcq(){return!(this.d===40&&this.f===32)&&A.bc.prototype.gcq.call(this)}}
A.hI.prototype={
aS(a,b){var t,s,r,q=this,p=A.v(a,!1,null,0)
q.a=p
t=q.b=A.l6(p)
if(t==null)return null
p=t.e.length
if(p===1)return q.al(0)
for(s=null,r=0;r<q.b.e.length;++r){b=q.al(r)
if(b==null)continue
if(s==null){b.w=B.j
s=b}else s.aZ(b)}return s},
al(a9){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7=null,a8=this.a
if(a8!=null){t=this.b
t=t==null||a9>=t.d}else t=!0
if(t)return a7
t=this.b.e
if(!(a9<t.length))return A.a(t,a9)
s=t[a9]
t=a8.a
a8=a8.b+s.e
r=s.d
q=J.jN(t,a8,a8+r)
p=new A.fJ(A.li())
u.D.a(q)
if(p.bm(q))return p.bO(q)
o=A.e3(!1,14)
o.aw(19778)
o.aF(r)
o.aF(0)
o.aF(0)
a8=A.v(q,!1,a7,0)
t=A.kT(A.v(J.V(B.e.gB(o.c),0,o.a),!1,a7,0))
r=a8.d
n=a8.l()
m=a8.l()
l=$.K()
l.$flags&2&&A.b(l)
l[0]=m
m=$.a4()
if(0>=m.length)return A.a(m,0)
k=m[0]
l[0]=a8.l()
m=m[0]
j=a8.m()
i=a8.m()
h=a8.l()
if(h>=14)A.aA(A.n("Unsupported BMP compression type: "+h))
if(!(h<14))return A.a(B.af,h)
h=B.af[h]
a8.l()
l[0]=a8.l()
l[0]=a8.l()
l=a8.l()
a8.l()
g=new A.fd(t,k,m,n,j,i,h,l,r)
g.dU(a8,t)
if(n!==40&&j!==1)return a7
f=l===0&&i<=8?40+4*B.a.O(1,i):40+4*l
t.b=f
o.a-=4
o.aF(f)
e=A.v(q,!1,a7,0)
d=new A.hw(!0)
d.a=e
d.b=g
c=d.al(0)
if(i>=32)return c
b=32-B.a.a1(k,32)
a=B.a.Y(b===32?k:k+b,8)
for(a8=m<0,t=m===0,m=1/m<0,a0=0;a0<B.a.Y(A.bc.prototype.gV.call(g),2);++a0){if(!(t?m:a8))a1=a0
else{r=c.a
r=r==null?a7:r.b
a1=(r==null?0:r)-1-a0}a2=e.ai(a)
e.d=e.d+(a2.c-a2.d)
r=c.a
a3=r==null?a7:r.L(0,a1,a7)
if(a3==null)a3=new A.G()
for(a4=0;a4<k;){a5=J.c(a2.a,a2.d++)
a6=7
for(;;){if(!(a6>-1&&a4<k))break
if((a5&B.a.W(1,a6))>>>0!==0)a3.su(0)
a3.F();++a4;--a6}}}return c}}
A.eW.prototype={}
A.bx.prototype={}
A.bY.prototype={}
A.dC.prototype={}
A.jt.prototype={
$5(a,b,c,d,e){return this.a.a3(this.b-a,b,c,d,e)},
$S:3}
A.ju.prototype={
$5(a,b,c,d,e){return this.a.a3(this.b-a,this.c-b,c,d,e)},
$S:3}
A.jv.prototype={
$5(a,b,c,d,e){return this.a.a3(a,this.b-b,c,d,e)},
$S:3}
A.jw.prototype={
$5(a,b,c,d,e){return this.a.a3(b,a,c,d,e)},
$S:3}
A.jx.prototype={
$5(a,b,c,d,e){return this.a.a3(this.b-b,a,c,d,e)},
$S:3}
A.jy.prototype={
$5(a,b,c,d,e){return this.a.a3(this.b-b,this.c-a,c,d,e)},
$S:3}
A.jz.prototype={
$5(a,b,c,d,e){return this.a.a3(b,this.b-a,c,d,e)},
$S:3}
A.hS.prototype={}
A.bA.prototype={}
A.hU.prototype={
jD(a){var t,s,r,q,p,o=this,n=A.v(u.L.a(a),!0,null,0)
o.a=n
t=n.cH(2,0)
if(J.c(t.a,t.d)!==255||J.c(t.a,t.d+1)!==216)return!1
if(o.bY()!==216)return!1
s=o.bY()
r=!1
q=!1
for(;;){if(s!==217){n=o.a
n=n.d<n.c}else n=!1
if(!n)break
p=o.a.m()
if(p<2)break
n=o.a
n.d=n.d+(p-2)
switch(s){case 192:case 193:case 194:r=!0
break
case 218:q=!0
break}s=o.bY()}return r&&q},
bS(a){var t,s,r,q,p,o,n,m,l,k,j,i=this
i.a=A.v(u.L.a(a),!0,null,0)
i.il()
if(i.y.length!==1)throw A.f(A.n("Only single frame JPEGs supported"))
t=i.d
for(s=t.z,r=t.y,q=i.as,p=0;p<s.length;++p){o=r.k(0,s[p])
n=o.a
m=t.f
l=o.b
k=t.r
j=i.h2(t,o)
if(n===m)n=0
else n=n===1&&m===4?2:1
if(l===k)m=0
else m=l===1&&k===4?2:1
B.c.A(q,new A.eW(j,n,m))}},
il(){var t,s,r,q,p,o,n=this
if(n.bY()!==216)throw A.f(A.n("Start Of Image marker not found."))
t=n.bY()
for(;;){if(t!==217){s=n.a
s===$&&A.d()
s=s.d<s.c}else s=!1
if(!s)break
A:{if(t>=208&&t<=215||t===1){t=n.bY()
break A}s=n.a
s===$&&A.d()
r=s.m()
if(r<2)A.aA(A.n("Invalid Block"))
s=n.a
q=s.ai(r-2)
p=s.d=s.d+(q.c-q.d)
switch(t){case 224:case 225:case 226:case 227:case 228:case 229:case 230:case 231:case 232:case 233:case 234:case 235:case 236:case 237:case 238:case 239:case 254:n.im(t,q)
break
case 219:n.ip(q)
break
case 192:case 193:case 194:n.is(t,q)
break
case 195:case 197:case 198:case 199:case 200:case 201:case 202:case 203:case 205:case 206:case 207:throw A.f(A.n("Unhandled frame type "+B.a.d7(t,16)))
case 196:n.io(q)
break
case 221:n.e=q.m()
break
case 218:n.iF(q)
break
case 255:if(J.c(s.a,p)!==255)--n.a.d
break
default:o=!1
if(J.c(s.a,p+-3)===255){s=n.a
if(J.c(s.a,s.d+-2)>=192){s=n.a
s=J.c(s.a,s.d+-2)<=254}else s=o}else s=o
if(s){n.a.d-=3
break}if(t!==0)throw A.f(A.n("Unknown JPEG marker "+B.a.d7(t,16)))
break}t=n.bY()}}},
bY(){var t,s=this,r=s.a
r===$&&A.d()
if(r.d>=r.c)return 0
do{do{t=s.a.G()
if(t!==255){r=s.a
r=r.d<r.c}else r=!1}while(r)
r=s.a
if(r.d>=r.c)return t
do{t=s.a.G()
if(t===255){r=s.a
r=r.d<r.c}else r=!1}while(r)
if(t===0){r=s.a
r=r.d<r.c}else r=!1}while(r)
return t},
ix(a){var t
for(t=0;t<12;++t)if(J.c(a.a,a.d++)!==B.jv[t])return
this.r=new A.bf("ICC_PROFILE",B.P,a.a2())},
iq(a){if(a.l()!==1165519206)return
if(a.m()!==0)return
this.w.bS(a)},
im(a,b){var t,s,r,q,p,o=this,n=b
if(a===224){t=n
s=!1
if(J.c(t.a,t.d)===74){t=n
if(J.c(t.a,t.d+1)===70){t=n
if(J.c(t.a,t.d+2)===73){t=n
if(J.c(t.a,t.d+3)===70){t=n
t=J.c(t.a,t.d+4)===0}else t=s}else t=s}else t=s}else t=s
if(t){t=new A.hW()
s=n
J.c(s.a,s.d+5)
s=n
J.c(s.a,s.d+6)
s=n
J.c(s.a,s.d+7)
s=n
J.c(s.a,s.d+8)
s=n
J.c(s.a,s.d+9)
s=n
J.c(s.a,s.d+10)
s=n
J.c(s.a,s.d+11)
s=n
s=J.c(s.a,s.d+12)
t.f=s
r=n
r=J.c(r.a,r.d+13)
t.r=r
o.b=t
n.cH(14+3*s*r,14)}}else if(a===225)o.iq(n)
else if(a===226)o.ix(n)
else if(a===238){t=n
s=!1
if(J.c(t.a,t.d)===65){t=n
if(J.c(t.a,t.d+1)===100){t=n
if(J.c(t.a,t.d+2)===111){t=n
if(J.c(t.a,t.d+3)===98){t=n
if(J.c(t.a,t.d+4)===101){t=n
t=J.c(t.a,t.d+5)===0}else t=s}else t=s}else t=s}else t=s}else t=s
if(t){q=new A.hS()
t=n
J.c(t.a,t.d+6)
t=n
J.c(t.a,t.d+7)
t=n
J.c(t.a,t.d+8)
t=n
J.c(t.a,t.d+9)
t=n
J.c(t.a,t.d+10)
t=n
q.d=J.c(t.a,t.d+11)
o.c=q}}else if(a===254)try{n.jt()}catch(p){}},
ip(a){var t,s,r,q,p,o,n,m,l
for(t=a.c,s=this.x;r=a.d,q=r<t,q;){q=a.a
a.d=r+1
p=J.c(q,r)
o=B.a.j(p,4)
p&=15
if(p>=4)throw A.f(A.n("Invalid number of quantization tables"))
if(s[p]==null)B.c.i(s,p,new Int16Array(64))
n=s[p]
for(r=o!==0,m=0;m<64;++m){l=r?a.m():J.c(a.a,a.d++)
n.toString
q=$.ho()
if(!(m<q.length))return A.a(q,m)
q=q[m]
n.$flags&2&&A.b(n)
if(!(q<64))return A.a(n,q)
n[q]=l}}if(q)throw A.f(A.n("Bad length for DQT block"))},
is(a,b){var t,s,r,q,p,o,n,m,l,k,j=this
if(j.d!=null)throw A.f(A.n("Duplicate JPG frame data found."))
t=A.D(u.p,u.d2)
s=A.j([],u.t)
r=new A.fz(t,s)
r.b=a===194
r.c=b.G()
r.d=b.m()
r.e=b.m()
q=b.G()
for(p=j.x,o=0;o<q;++o){n=J.c(b.a,b.d++)
m=J.c(b.a,b.d++)
l=B.a.j(m,4)
k=J.c(b.a,b.d++)
B.c.A(s,n)
t.i(0,n,new A.bA(l&15,m&15,p,k))}r.jn()
j.d=r
B.c.A(j.y,r)},
io(a){var t,s,r,q,p,o,n,m,l,k,j,i
for(t=a.c,s=this.Q,r=this.z;q=a.d,q<t;){p=a.a
a.d=q+1
o=J.c(p,q)
n=new Uint8Array(16)
for(m=0,l=0;l<16;++l){q=J.c(a.a,a.d++)
if(!(l<16))return A.a(n,l)
n[l]=q
m+=n[l]}k=a.ai(m)
a.d=a.d+(k.c-k.d)
j=k.a2()
if((o&16)!==0){o-=16
i=r}else i=s
if(i.length<=o)B.c.st(i,o+1)
B.c.i(i,o,this.i_(n,j))}},
iF(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=this,c=a.G()
if(c<1||c>4)throw A.f(A.n("Invalid SOS block"))
t=d.d
t.toString
s=A.j([],u.b7)
for(r=d.z,q=d.Q,p=t.y,o=u.C,n=0;n<c;++n){m=J.c(a.a,a.d++)
l=J.c(a.a,a.d++)
if(!p.ae(m))throw A.f(A.n("Invalid Component in SOS block"))
k=p.k(0,m)
k.toString
j=B.a.j(l,4)&15
i=l&15
h=q.length
if(j<h){if(!(j<h))return A.a(q,j)
h=q[j]
h.toString
k.w=o.a(h)}h=r.length
if(i<h){if(!(i<h))return A.a(r,i)
h=r[i]
h.toString
k.x=o.a(h)}B.c.A(s,k)}g=a.G()
f=a.G()
e=a.G()
r=B.a.j(e,4)
q=d.a
q===$&&A.d()
r=new A.fA(q,t,s,d.e,g,f,r&15,e&15)
q=t.w
q===$&&A.d()
r.f=q
r.r=t.b
r.bF()},
i_(a,b){var t,s,r,q,p,o,n,m,l=A.j([],u.e8),k=16
for(;;){if(!(k>0&&a[k-1]===0))break;--k}t=u.fe
B.c.A(l,new A.dh(A.P(2,null,!1,t)))
if(0>=l.length)return A.a(l,0)
s=l[0]
for(r=b.length,q=0,p=0;p<k;){for(o=0;o<a[p];++o){if(0>=l.length)return A.a(l,-1)
s=l.pop()
n=s.b
if(!(q>=0&&q<r))return A.a(b,q)
B.c.i(s.a,n,new A.dC(b[q]))
while(n=s.b,n>0){if(0>=l.length)return A.a(l,-1)
s=l.pop()}s.b=n+1
B.c.A(l,s)
for(;l.length<=p;s=m){n=A.P(2,null,!1,t)
m=new A.dh(n)
B.c.A(l,m)
B.c.i(s.a,s.b,new A.bY(n))}++q}++p
if(p<k){n=A.P(2,null,!1,t)
m=new A.dh(n)
B.c.A(l,m)
B.c.i(s.a,s.b,new A.bY(n))
s=m}}if(0>=l.length)return A.a(l,0)
return l[0].a},
h2(a,a0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=a0.e
b===$&&A.d()
t=a0.f
t===$&&A.d()
s=b<<3>>>0
r=new Int32Array(64)
q=new Uint8Array(64)
p=t*8
o=A.P(p,null,!1,u.aD)
for(n=a0.c,m=a0.d,l=0,k=0;k<t;++k){j=k<<3>>>0
for(i=0;i<8;++i,l=h){h=l+1
B.c.i(o,l,new Uint8Array(s))}for(g=0;g<b;++g){if(!(m>=0&&m<4))return A.a(n,m)
f=n[m]
f.toString
e=a0.r
e===$&&A.d()
if(!(k<e.length))return A.a(e,k)
e=e[k]
if(!(g<e.length))return A.a(e,g)
A.qi(f,e[g],q,r)
d=g<<3>>>0
for(f=d+8,c=0;c<8;++c){e=j+c
if(!(e<p))return A.a(o,e)
e=o[e]
if(e!=null)B.e.ar(e,d,f,q,c<<3>>>0)}}}return o}}
A.dh.prototype={}
A.fz.prototype={
jn(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=this
for(t=b.y,s=A.l(t).v("O<1>"),r=new A.O(t,t.r,t.e,s);r.F();){q=t.k(0,r.d)
b.f=Math.max(b.f,q.a)
b.r=Math.max(b.r,q.b)}r=b.e
r.toString
b.w=B.b.b0(r/8/b.f)
r=b.d
r.toString
b.x=B.b.b0(r/8/b.r)
for(s=new A.O(t,t.r,t.e,s),r=u.fv,p=u.an,o=u.f0;s.F();){n=t.k(0,s.d)
n.toString
m=b.e
m.toString
l=n.a
k=B.b.b0(B.b.b0(m/8)*l/b.f)
m=b.d
m.toString
j=n.b
i=B.b.b0(B.b.b0(m/8)*j/b.r)
h=b.w*l
g=b.x*j
f=J.ag(g,o)
for(e=0;e<g;++e){d=J.ag(h,p)
for(c=0;c<h;++c)d[c]=new Int32Array(64)
f[e]=d}n.e=k
n.f=i
n.r=r.a(f)}}}
A.hW.prototype={}
A.fA.prototype={
bF(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=c.y,a=b.length,a0=c.r
a0.toString
if(a0)if(c.Q===0)t=c.at===0?c.ghl():c.ghn()
else t=c.at===0?c.ghc():c.ghe()
else t=c.ghi()
a0=a===1
if(a0){if(0>=a)return A.a(b,0)
s=b[0]
r=s.e
r===$&&A.d()
s=s.f
s===$&&A.d()
q=r*s}else{s=c.f
s===$&&A.d()
r=c.b.x
r===$&&A.d()
q=s*r}s=c.z
if(s==null||s===0)c.z=q
for(s=c.a,r=u.V,p=0;p<q;){for(o=0;o<a;++o){if(!(o<b.length))return A.a(b,o)
b[o].y=0}c.CW=0
if(a0){if(0>=b.length)return A.a(b,0)
n=b[0]
m=0
for(;;){l=c.z
l.toString
if(!(m<l))break
r.a(t)
l=n.e
l===$&&A.d()
k=B.a.au(p,l)
j=B.a.a1(p,l)
l=n.r
l===$&&A.d()
if(!(k>=0&&k<l.length))return A.a(l,k)
l=l[k]
if(!(j>=0&&j<l.length))return A.a(l,j)
t.$2(n,l[j]);++p;++m}}else{m=0
for(;;){l=c.z
l.toString
if(!(m<l))break
for(o=0;o<a;++o){if(!(o<b.length))return A.a(b,o)
n=b[o]
i=n.a
h=n.b
for(g=0;g<h;++g)for(f=0;f<i;++f)c.hq(n,t,p,g,f)}++p;++m}}c.ch=0
if(p>=q)break
e=J.c(s.a,s.d)
d=J.c(s.a,s.d+1)
if(e===255)if(d>=208&&d<=215)s.d+=2
else break}},
c_(){var t,s=this,r=s.ch
if(r>0){--r
s.ch=r
return B.a.bs(s.ay,r)&1}r=s.a
if(r.d>=r.c)return null
t=r.G()
s.ay=t
if(t===255)if(r.G()!==0)return null
s.ch=7
return B.a.j(s.ay,7)&1},
cg(a){var t,s,r=new A.bY(u.C.a(a))
while(t=this.c_(),t!=null){if(r instanceof A.bY){s=r.a
if(t>>>0!==t||t>=2)return A.a(s,t)
r=s[t]}if(r instanceof A.dC)return r.a}return null},
dA(a){var t,s
for(t=0;a>0;){s=this.c_()
if(s==null)return null
t=(t<<1|s)>>>0;--a}return t},
cj(a){var t
if(a==null)return 0
if(a===1)return this.c_()===1?1:-1
t=this.dA(a)
if(t==null)return 0
if(t>=B.a.W(1,a-1))return t
return t+B.a.O(-1,a)+1},
hj(a,b){var t,s,r,q,p,o,n,m,l=this
u.L.a(b)
t=a.w
t===$&&A.d()
s=l.cg(t)
r=s===0?0:l.cj(s)
t=a.y
t===$&&A.d()
t+=r
a.y=t
b.$flags&2&&A.b(b)
b[0]=t
for(q=1;q<64;){t=a.x
t===$&&A.d()
p=l.cg(t)
if(p==null)break
o=p&15
n=p>>>4
if(o===0){if(n<15)break
q+=16
continue}q+=n
o=l.cj(o)
t=$.ho()
if(!(q>=0&&q<t.length))return A.a(t,q)
m=t[q]
b.$flags&2&&A.b(b)
if(!(m<64))return A.a(b,m)
b[m]=o;++q}},
hm(a,b){var t,s,r
u.L.a(b)
t=a.w
t===$&&A.d()
s=this.cg(t)
r=s===0?0:B.a.O(this.cj(s),this.ax)
t=a.y
t===$&&A.d()
t+=r
a.y=t
b.$flags&2&&A.b(b)
b[0]=t},
ho(a,b){var t,s
u.L.a(b)
t=b[0]
s=this.c_()
s.toString
s=B.a.O(s,this.ax)
b.$flags&2&&A.b(b)
b[0]=(t|s)>>>0},
hd(a,b){var t,s,r,q,p,o,n,m,l=this
u.L.a(b)
t=l.CW
if(t>0){l.CW=t-1
return}s=l.Q
r=l.as
for(t=l.ax;s<=r;){q=a.x
q===$&&A.d()
q=l.cg(q)
q.toString
p=q&15
o=q>>>4
if(p===0){if(o<15){t=l.dA(o)
t.toString
l.CW=t+B.a.O(1,o)-1
break}s+=16
continue}s+=o
q=$.ho()
if(!(s>=0&&s<q.length))return A.a(q,s)
n=q[s]
q=l.cj(p)
m=B.a.O(1,t)
b.$flags&2&&A.b(b)
if(!(n<64))return A.a(b,n)
b[n]=q*m;++s}},
hf(a,b){var t,s,r,q,p,o,n,m,l,k=this
u.L.a(b)
t=k.Q
s=k.as
A:for(r=k.ax,q=0;t<=s;){p=$.ho()
if(!(t>=0&&t<p.length))return A.a(p,t)
o=p[t]
p=k.cx
switch(p){case 0:p=a.x
p===$&&A.d()
n=k.cg(p)
if(n==null)throw A.f(A.n("Invalid progressive encoding"))
m=n&15
q=n>>>4
if(m===0)if(q<15){p=k.dA(q)
p.toString
k.CW=p+B.a.O(1,q)
k.cx=4}else{k.cx=1
q=16}else{if(m!==1)throw A.f(A.n("invalid ACn encoding"))
k.cy=k.cj(m)
k.cx=q!==0?2:3}continue A
case 1:case 2:if(!(o<64))return A.a(b,o)
l=b[o]
if(l!==0){p=k.c_()
p.toString
p=B.a.O(p,r)
b.$flags&2&&A.b(b)
if(!(o<64))return A.a(b,o)
b[o]=l+p}else{--q
if(q===0)k.cx=p===2?3:0}break
case 3:if(!(o<64))return A.a(b,o)
p=b[o]
if(p!==0){l=k.c_()
l.toString
l=B.a.O(l,r)
b.$flags&2&&A.b(b)
if(!(o<64))return A.a(b,o)
b[o]=p+l}else{p=k.cy
p===$&&A.d()
p=B.a.O(p,r)
b.$flags&2&&A.b(b)
if(!(o<64))return A.a(b,o)
b[o]=p
k.cx=0}break
case 4:if(!(o<64))return A.a(b,o)
p=b[o]
if(p!==0){l=k.c_()
l.toString
l=B.a.O(l,r)
b.$flags&2&&A.b(b)
if(!(o<64))return A.a(b,o)
b[o]=p+l}break}++t}if(k.cx===4)if(--k.CW===0)k.cx=0},
hq(a,b,c,d,e){var t,s,r,q,p
u.V.a(b)
t=this.f
t===$&&A.d()
s=B.a.au(c,t)*a.b+d
r=B.a.a1(c,t)*a.a+e
t=a.r
t===$&&A.d()
q=t.length
if(s>=q)return
if(!(s>=0))return A.a(t,s)
t=t[s]
p=t.length
if(r>=p)return
if(!(r>=0))return A.a(t,r)
b.$2(a,t[r])}}
A.fy.prototype={
bm(a){var t=a.length,s=!0
if(t>=2){if(0>=t)return A.a(a,0)
if(a[0]===255){if(1>=t)return A.a(a,1)
t=a[1]!==216}else t=s}else t=s
if(t)return!1
return A.lo().jD(a)},
aS(a,b){var t=A.lo()
t.bS(a)
if(t.y.length!==1)throw A.f(A.n("only single frame JPEGs supported"))
return A.q4(t)},
bO(a){return this.aS(a,null)}}
A.hT.prototype={
ad(){return"JpegChroma."+this.b}}
A.hV.prototype={
ft(a){a=B.a.h(B.a.J(a,1,100))
if(this.at===a)return
this.hV(a<50?B.b.bQ(5000/a):B.a.bQ(200-a*2))
this.at=a},
j8(b4,b5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2=this,b3=A.e3(!0,8192)
b2.bC(b3,216)
b2.bC(b3,224)
b3.aw(16)
b3.C(74)
b3.C(70)
b3.C(73)
b3.C(70)
b3.C(0)
b3.C(1)
b3.C(1)
b3.C(0)
b3.aw(1)
b3.aw(1)
b3.C(0)
b3.C(0)
b2.iR(b3,b4.gbG())
t=b4.c
if(t!=null){b2.bC(b3,226)
s=t.j7()
r=A.j([73,67,67,95,80,82,79,70,73,76,69,0],u.t)
b3.aw(14+s.length)
b3.aV(r)
b3.aV(s)}b2.iQ(b3)
t=b4.ga5()
q=b4.gV()
b2.bC(b3,192)
b3.aw(17)
b3.C(8)
b3.aw(q)
b3.aw(t)
b3.C(3)
b3.C(1)
t=b5===B.b5
b3.C(t?17:34)
b3.C(0)
b3.C(2)
b3.C(17)
b3.C(1)
b3.C(3)
b3.C(17)
b3.C(1)
b2.iP(b3)
b2.bC(b3,218)
b3.aw(12)
b3.C(3)
b3.C(1)
b3.C(0)
b3.C(2)
b3.C(17)
b3.C(3)
b3.C(17)
b3.C(0)
b3.C(63)
b3.C(0)
b2.ax=0
b2.ay=7
p=b4.ga5()
o=b4.gV()
n=b4.f
if(n==null)n=B.cC
if(t){m=new Float32Array(64)
l=new Float32Array(64)
k=new Float32Array(64)
for(t=b2.c,q=b2.d,j=0,i=0,h=0,g=0;g<o;g+=8)for(f=0;f<p;f+=8){b2.cc(b4,f,g,p,o,m,l,k,n)
e=b2.e
d=b2.r
d===$&&A.d()
j=b2.bA(b3,m,t,j,e,d)
d=b2.f
e=b2.w
e===$&&A.d()
i=b2.bA(b3,l,q,i,d,e)
h=b2.bA(b3,k,q,h,b2.f,b2.w)}}else{t=u.h4
m=J.c4(4,t)
for(c=0;c<4;++c)m[c]=new Float32Array(64)
l=J.c4(4,t)
for(c=0;c<4;++c)l[c]=new Float32Array(64)
k=J.c4(4,t)
for(c=0;c<4;++c)k[c]=new Float32Array(64)
b=new Float32Array(64)
a=new Float32Array(64)
for(t=b2.c,q=b2.d,j=0,i=0,h=0,g=0;g<o;g+=16)for(e=g+8,f=0;f<p;f+=16){d=m[0]
a0=l[0]
a1=k[0]
b2.cc(b4,f,g,p,o,d,a0,a1,n)
a2=f+8
a3=m[1]
a4=l[1]
a5=k[1]
b2.cc(b4,a2,g,p,o,a3,a4,a5,n)
a6=m[2]
a7=l[2]
a8=k[2]
b2.cc(b4,f,e,p,o,a6,a7,a8,n)
a9=m[3]
b0=l[3]
b1=k[3]
b2.cc(b4,a2,e,p,o,a9,b0,b1,n)
b2.ed(b,a0,a4,a7,b0)
b2.ed(a,a1,a5,a8,b1)
b1=b2.e
a8=b2.r
a8===$&&A.d()
j=b2.bA(b3,a9,t,b2.bA(b3,a6,t,b2.bA(b3,a3,t,b2.bA(b3,d,t,j,b1,a8),b2.e,b2.r),b2.e,b2.r),b2.e,b2.r)
a8=b2.f
b1=b2.w
b1===$&&A.d()
i=b2.bA(b3,b,q,i,a8,b1)
h=b2.bA(b3,a,q,h,b2.f,b2.w)}}t=b2.ay
if(t>=0){++t
b2.bB(b3,A.j([B.a.W(1,t)-1,t],u.t))}b2.bC(b3,217)
return J.V(B.e.gB(b3.c),0,b3.a)},
cc(a,b,c,d,e,a0,a1,a2,a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f
for(t=this.as,s=c+1,r=0;r<64;++r){q=r>>>3
p=c+q
o=b+(r&7)
if(p>=e)p-=s+q-e
if(o>=d)o-=o-d+1
n=a.a
m=n==null?null:n.L(o,p,null)
if(m==null)m=new A.G()
if(m.gK()!==B.f)m=m.b1(B.f)
if(m.gt(m)>3){l=m.gU()
k=1-l
m.sn(B.b.aD(m.gn()*l+a3.gn()*k))
m.sp(B.b.aD(m.gp()*l+a3.gp()*k))
m.sq(B.b.aD(m.gq()*l+a3.gq()*k))}j=B.b.h(m.gn())
i=B.b.h(m.gp())
h=B.b.h(m.gq())
if(!(j>=0&&j<2048))return A.a(t,j)
n=t[j]
g=i+256
if(!(g>=0&&g<2048))return A.a(t,g)
g=t[g]
f=h+512
if(!(f>=0&&f<2048))return A.a(t,f)
f=B.a.j(n+g+t[f],16)
a0.$flags&2&&A.b(a0)
if(!(r<64))return A.a(a0,r)
a0[r]=f-128
f=j+768
if(!(f<2048))return A.a(t,f)
f=t[f]
g=i+1024
if(!(g>=0&&g<2048))return A.a(t,g)
g=t[g]
n=h+1280
if(!(n>=0&&n<2048))return A.a(t,n)
n=B.a.j(f+g+t[n],16)
a1.$flags&2&&A.b(a1)
if(!(r<64))return A.a(a1,r)
a1[r]=n-128
n=j+1280
if(!(n<2048))return A.a(t,n)
n=t[n]
g=i+1536
if(!(g>=0&&g<2048))return A.a(t,g)
g=t[g]
f=h+1792
if(!(f>=0&&f<2048))return A.a(t,f)
f=B.a.j(n+g+t[f],16)
a2.$flags&2&&A.b(a2)
if(!(r<64))return A.a(a2,r)
a2[r]=f-128}},
ed(a,b,c,d,e){var t,s,r,q,p,o,n,m
for(t=a.$flags|0,s=0;s<64;++s){if(s<32)r=B.a.a1(s,8)<4?b:c
else r=B.a.a1(s,8)<4?d:e
q=(B.a.Y(B.a.a1(s,32),8)<<4>>>0)+(B.a.a1(s,4)<<1>>>0)
if(!(q<64))return A.a(r,q)
p=r[q]
o=q+1
if(!(o<64))return A.a(r,o)
o=r[o]
n=q+8
if(!(n<64))return A.a(r,n)
n=r[n]
m=q+9
if(!(m<64))return A.a(r,m)
m=r[m]
t&2&&A.b(a)
if(!(s<64))return A.a(a,s)
a[s]=(p+o+n+m)/4}},
bC(a,b){a.C(255)
a.C(b&255)},
hV(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this
for(t=c.a,s=t.$flags|0,r=0;r<64;++r){q=B.b.bQ((B.i2[r]*a+50)/100)
if(q<1)q=1
else if(q>255)q=255
p=B.U[r]
s&2&&A.b(t)
if(!(p<64))return A.a(t,p)
t[p]=q}for(s=c.b,p=s.$flags|0,o=0;o<64;++o){n=B.b.bQ((B.en[o]*a+50)/100)
if(n<1)n=1
else if(n>255)n=255
m=B.U[o]
p&2&&A.b(s)
if(!(m<64))return A.a(s,m)
s[m]=n}for(p=c.c,m=p.$flags|0,l=c.d,k=l.$flags|0,j=0,i=0;i<8;++i)for(h=0;h<8;++h){if(!(j>=0&&j<64))return A.a(B.U,j)
g=B.U[j]
if(!(g<64))return A.a(t,g)
f=t[g]
e=B.bg[i]
d=B.bg[h]
m&2&&A.b(p)
p[j]=1/(f*e*d*8)
g=s[g]
k&2&&A.b(l)
l[j]=1/(g*e*d*8);++j}},
cL(a,b){var t,s,r,q,p,o,n,m=u.L
m.a(a)
m.a(b)
m=u.t
t=A.j([A.j([],m)],u.ca)
for(s=b.length,r=0,q=0,p=1;p<=16;++p){for(o=1;o<=a[p];++o){if(!(q>=0&&q<s))return A.a(b,q)
n=b[q]
if(t.length<=n)B.c.st(t,n+1)
B.c.i(t,n,A.j([r,p],m));++q;++r}r*=2}return t},
hT(){var t,s,r,q,p,o,n,m,l,k,j
for(t=this.y,s=this.x,r=u.t,q=1,p=2,o=1;o<=15;++o){for(n=q;n<p;++n){m=32767+n
B.c.i(t,m,o)
B.c.i(s,m,A.j([n,o],r))}for(m=p-1,l=-m,k=-q;l<=k;++l){j=32767+l
B.c.i(t,j,o)
B.c.i(s,j,A.j([m+l,o],r))}q=q<<1>>>0
p=p<<1>>>0}},
hW(){var t,s,r
for(t=this.as,s=t.$flags|0,r=0;r<256;++r){s&2&&A.b(t)
t[r]=19595*r
t[r+256]=38470*r
t[r+512]=7471*r+32768
t[r+768]=-11059*r
t[r+1024]=-21709*r
t[r+1280]=32768*r+8421375
t[r+1536]=-27439*r
t[r+1792]=-5329*r}},
hJ(d5,d6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,d0,d1,d2,d3,d4=u.H
d4.a(d5)
d4.a(d6)
for(d4=d5.$flags|0,t=0,s=0;s<8;++s){if(!(t<64))return A.a(d5,t)
r=d5[t]
q=t+1
if(!(q<64))return A.a(d5,q)
p=d5[q]
o=t+2
if(!(o<64))return A.a(d5,o)
n=d5[o]
m=t+3
if(!(m<64))return A.a(d5,m)
l=d5[m]
k=t+4
if(!(k<64))return A.a(d5,k)
j=d5[k]
i=t+5
if(!(i<64))return A.a(d5,i)
h=d5[i]
g=t+6
if(!(g<64))return A.a(d5,g)
f=d5[g]
e=t+7
if(!(e<64))return A.a(d5,e)
d=d5[e]
c=r+d
b=r-d
a=p+f
a0=p-f
a1=n+h
a2=n-h
a3=l+j
a4=c+a3
a5=c-a3
a6=a+a1
d4&2&&A.b(d5)
if(!(t<64))return A.a(d5,t)
d5[t]=a4+a6
if(!(k<64))return A.a(d5,k)
d5[k]=a4-a6
a7=(a-a1+a5)*0.707106781
if(!(o<64))return A.a(d5,o)
d5[o]=a5+a7
if(!(g<64))return A.a(d5,g)
d5[g]=a5-a7
a4=l-j+a2
a8=a0+b
a9=(a4-a8)*0.382683433
b0=0.5411961*a4+a9
b1=1.306562965*a8+a9
b2=(a2+a0)*0.707106781
b3=b+b2
b4=b-b2
if(!(i<64))return A.a(d5,i)
d5[i]=b4+b0
if(!(m<64))return A.a(d5,m)
d5[m]=b4-b0
if(!(q<64))return A.a(d5,q)
d5[q]=b3+b1
if(!(e<64))return A.a(d5,e)
d5[e]=b3-b1
t+=8}for(t=0,s=0;s<8;++s){if(!(t<64))return A.a(d5,t)
r=d5[t]
q=t+8
if(!(q<64))return A.a(d5,q)
p=d5[q]
o=t+16
if(!(o<64))return A.a(d5,o)
n=d5[o]
m=t+24
if(!(m<64))return A.a(d5,m)
l=d5[m]
k=t+32
if(!(k<64))return A.a(d5,k)
j=d5[k]
i=t+40
if(!(i<64))return A.a(d5,i)
h=d5[i]
g=t+48
if(!(g<64))return A.a(d5,g)
f=d5[g]
e=t+56
if(!(e<64))return A.a(d5,e)
d=d5[e]
b5=r+d
b6=r-d
b7=p+f
b8=p-f
b9=n+h
c0=n-h
c1=l+j
c2=b5+c1
c3=b5-c1
c4=b7+b9
d4&2&&A.b(d5)
if(!(t<64))return A.a(d5,t)
d5[t]=c2+c4
if(!(k<64))return A.a(d5,k)
d5[k]=c2-c4
c5=(b7-b9+c3)*0.707106781
if(!(o<64))return A.a(d5,o)
d5[o]=c3+c5
if(!(g<64))return A.a(d5,g)
d5[g]=c3-c5
c2=l-j+c0
c6=b8+b6
c7=(c2-c6)*0.382683433
c8=0.5411961*c2+c7
c9=1.306562965*c6+c7
d0=(c0+b8)*0.707106781
d1=b6+d0
d2=b6-d0
if(!(i<64))return A.a(d5,i)
d5[i]=d2+c8
if(!(m<64))return A.a(d5,m)
d5[m]=d2-c8
if(!(q<64))return A.a(d5,q)
d5[q]=d1+c9
if(!(e<64))return A.a(d5,e)
d5[e]=d1-c9;++t}for(d4=this.z,s=0;s<64;++s){d3=d5[s]*d6[s]
B.c.i(d4,s,d3>0?B.b.h(d3+0.5):B.b.h(d3-0.5))}return d4},
iR(a,b){var t,s
if(b.gaU(0))return
t=A.e3(!1,8192)
b.aG(t)
s=J.V(B.e.gB(t.c),0,t.a)
this.bC(a,225)
a.aw(s.length+8)
a.aF(1165519206)
a.aw(0)
a.aV(s)},
iQ(a){var t,s,r
this.bC(a,219)
a.aw(132)
a.C(0)
for(t=this.a,s=0;s<64;++s)a.C(t[s])
a.C(1)
for(t=this.b,r=0;r<64;++r)a.C(t[r])},
iP(a){var t,s,r,q,p,o,n,m
this.bC(a,196)
a.aw(418)
a.C(0)
for(t=0;t<16;){++t
a.C(B.bR[t])}for(s=0;s<=11;++s)a.C(B.a7[s])
a.C(16)
for(r=0;r<16;){++r
a.C(B.b9[r])}for(q=0;q<=161;++q)a.C(B.bi[q])
a.C(1)
for(p=0;p<16;){++p
a.C(B.bt[p])}for(o=0;o<=11;++o)a.C(B.a7[o])
a.C(17)
for(n=0;n<16;){++n
a.C(B.bn[n])}for(m=0;m<=161;++m)a.C(B.bB[m])},
bA(a,b,a0,a1,a2,a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=this,c=u.H
c.a(b)
c.a(a0)
u.fl.a(a2)
u.d.a(a3)
c=a3.length
if(0>=c)return A.a(a3,0)
t=a3[0]
if(240>=c)return A.a(a3,240)
s=a3[240]
r=d.hJ(b,a0)
for(c=d.Q,q=0;q<64;++q)B.c.i(c,B.U[q],r[q])
p=c[0]
p.toString
o=p-a1
if(o===0){if(0>=a2.length)return A.a(a2,0)
n=a2[0]
n.toString
d.bB(a,n)}else{m=32767+o
a2.toString
n=d.y
if(!(m>=0&&m<65535))return A.a(n,m)
n=n[m]
n.toString
if(!(n<a2.length))return A.a(a2,n)
n=a2[n]
n.toString
d.bB(a,n)
n=d.x[m]
n.toString
d.bB(a,n)}l=63
for(;;){if(!(l>0&&c[l]===0))break;--l}if(l===0){t.toString
d.bB(a,t)
return p}for(n=d.y,k=d.x,j=1;j<=l;){i=j
for(;;){if(!(i>=0&&i<64))return A.a(c,i)
if(!(c[i]===0&&i<=l))break;++i}h=i-j
if(h>=16){g=B.a.j(h,4)
for(f=1;f<=g;++f){s.toString
d.bB(a,s)}h&=15}e=c[i]
e.toString
m=32767+e
if(!(m>=0&&m<65535))return A.a(n,m)
e=n[m]
e.toString
e=(h<<4>>>0)+e
if(!(e<a3.length))return A.a(a3,e)
e=a3[e]
e.toString
d.bB(a,e)
e=k[m]
e.toString
d.bB(a,e)
j=i+1}if(l!==63){t.toString
d.bB(a,t)}return p},
bB(a,b){var t,s,r,q=this
u.L.a(b)
t=b.length
if(0>=t)return A.a(b,0)
s=b[0]
if(1>=t)return A.a(b,1)
r=b[1]-1
while(r>=0){if((s&B.a.W(1,r))>>>0!==0)q.ax=(q.ax|B.a.W(1,q.ay))>>>0;--r
if(--q.ay<0){t=q.ax
if(t===255){a.C(255)
a.C(0)}else a.C(t)
q.ay=7
q.ax=0}}}}
A.d2.prototype={
ad(){return"PngDisposeMode."+this.b}}
A.eg.prototype={
ad(){return"PngBlendMode."+this.b}}
A.eh.prototype={}
A.fr.prototype={}
A.bD.prototype={
ad(){return"PngFilterType."+this.b}}
A.fK.prototype={
sR(a){this.w=u.di.a(a)},
sjA(a){this.x=u.T.a(a)},
$iJ:1}
A.fs.prototype={}
A.fJ.prototype={
bm(a){var t,s=A.v(a,!0,null,0).ag(8)
for(t=0;t<8;++t)if(J.c(s.a,s.d+t)!==B.bG[t])return!1
return!0},
aP(b6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3=this,b4=null,b5=A.v(b6,!0,b4,0)
b3.d=b5
t=b5.ag(8)
for(s=0;s<8;++s)if(J.c(t.a,t.d+s)!==B.bG[s])return b4
for(b5=b3.a,r=b5.cy,q=u.t,p=b5.db,o=u.L,n=b5.ax;;){m=b3.d
l=m.d-m.b
k=m.l()
j=b3.d.ah(4)
switch(j){case"tEXt":m=b3.d
i=m.ai(k)
m.d=m.d+(i.c-i.d)
h=i.a2()
g=h.length
for(s=0;s<g;++s)if(h[s]===0){m=s+1
n.i(0,B.aP.bO(new Uint8Array(h.subarray(0,A.b6(0,s,g)))),B.aP.bO(new Uint8Array(h.subarray(m,A.b6(m,b4,g)))))
break}b3.d.d+=4
break
case"pHYs":m=b3.d
i=m.ai(k)
m.d=m.d+(i.c-i.d)
f=A.o(i,b4,0)
f.l()
f.l()
J.c(f.a,f.d++)
b3.d.d+=4
break
case"IHDR":m=b3.d
i=m.ai(k)
m.d=m.d+(i.c-i.d)
e=A.o(i,b4,0)
d=e.a2()
b5.a=e.l()
b5.b=e.l()
b5.c=J.c(e.a,e.d++)
b5.d=J.c(e.a,e.d++)
J.c(e.a,e.d++)
b5.f=J.c(e.a,e.d++)
b5.r=J.c(e.a,e.d++)
m=b5.d
if(!(m===0||m===2||m===3||m===4||m===6))return b4
if(b5.f!==0)return b4
switch(m){case 0:if(!B.c.aR(A.j([1,2,4,8,16],q),b5.c))return b4
break
case 2:if(!B.c.aR(A.j([8,16],q),b5.c))return b4
break
case 3:if(!B.c.aR(A.j([1,2,4,8],q),b5.c))return b4
break
case 4:if(!B.c.aR(A.j([8,16],q),b5.c))return b4
break
case 6:if(!B.c.aR(A.j([8,16],q),b5.c))return b4
break}if(b3.d.l()!==A.cv(o.a(d),A.cv(new A.aJ(j),0)))throw A.f(A.n("Invalid "+j+" checksum"))
break
case"PLTE":m=b3.d
i=m.ai(k)
m.d=m.d+(i.c-i.d)
b5.sR(i.a2())
if(b3.d.l()!==A.cv(o.a(o.a(b5.w)),A.cv(new A.aJ(j),0)))throw A.f(A.n("Invalid "+j+" checksum"))
break
case"tRNS":m=b3.d
i=m.ai(k)
m.d=m.d+(i.c-i.d)
b5.sjA(i.a2())
c=b3.d.l()
m=b5.x
m.toString
if(c!==A.cv(o.a(m),A.cv(new A.aJ(j),0)))throw A.f(A.n("Invalid "+j+" checksum"))
break
case"IEND":b3.d.d+=4
break
case"gAMA":if(k!==4)throw A.f(A.n("Invalid gAMA chunk"))
b3.d.l()
b3.d.d+=4
break
case"IDAT":B.c.A(p,l)
m=b3.d
m.d=(m.d+=k)+4
break
case"acTL":b5.CW=b3.d.l()
b3.d.l()
b3.d.d+=4
break
case"fcTL":b3.d.l()
b=b3.d.l()
a=b3.d.l()
a0=b3.d.l()
a1=b3.d.l()
a2=b3.d.m()
a3=b3.d.m()
m=b3.d
a4=J.c(m.a,m.d++)
m=b3.d
a5=J.c(m.a,m.d++)
if(!(a4>=0&&a4<3))return A.a(B.b8,a4)
m=B.b8[a4]
if(!(a5>=0&&a5<2))return A.a(B.bu,a5)
a6=B.bu[a5]
B.c.A(r,new A.fr(A.j([],q),b,a,a0,a1,a2,a3,m,a6))
b3.d.d+=4
break
case"fdAT":b3.d.l()
B.c.A(B.c.gf7(r).y,l)
m=b3.d
m.d=(m.d+=k-4)+4
break
case"bKGD":m=b5.d
if(m===3){m=b3.d
a7=J.c(m.a,m.d++);--k
a8=a7*3
m=b5.w
a6=m.length
if(!(a8>=0&&a8<a6))return A.a(m,a8)
a9=m[a8]
b0=a8+1
if(!(b0<a6))return A.a(m,b0)
b1=m[b0]
b0=a8+2
if(!(b0<a6))return A.a(m,b0)
b2=m[b0]
m=b5.x
if(m!=null){m=B.e.aR(m,a7)?0:255
a6=new Uint8Array(4)
a6[0]=a9
a6[1]=b1
a6[2]=b2
a6[3]=m
b5.z=new A.bT(a6)}else{m=new Uint8Array(3)
m[0]=a9
m[1]=b1
m[2]=b2
b5.z=new A.eV(m)}}else if(m===0||m===4){b3.d.m()
k-=2}else if(m===2||m===6){m=b3.d
m.m()
m.m()
m.m()
k-=24}if(k>0)b3.d.d+=k
b3.d.d+=4
break
case"iCCP":b5.Q=b3.d.cv()
m=b3.d
J.c(m.a,m.d++)
m=b5.Q
a6=b3.d
i=a6.ai(k-(m.length+2))
a6.d=a6.d+(i.c-i.d)
b5.at=i.a2()
b3.d.d+=4
break
case"cICP":m=b3.d
a6=m.d
if(k===4){b0=m.a
m.d=a6+1
J.c(b0,a6)
a6=b3.d
J.c(a6.a,a6.d++)
a6=b3.d
J.c(a6.a,a6.d++)
a6=b3.d
J.c(a6.a,a6.d++)}else m.d=a6+k
b3.d.d+=4
break
default:m=b3.d
m.d=(m.d+=k)+4
break}if(j==="IEND")break
m=b3.d
if(m.d>=m.c)return b4}return b5},
al(c2){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4=this,b5=null,b6=null,b7=b4.a,b8=b7.a,b9=b7.b,c0=b7.cy,c1=c0.length
if(c1===0||c2===0){s=A.j([],u.h)
c0=b7.db
r=c0.length
for(c1=u.L,q=0,p=0;p<r;++p){o=b4.d
o===$&&A.d()
if(!(p<c0.length))return A.a(c0,p)
o.d=c0[p]
n=o.l()
m=b4.d.ah(4)
o=b4.d
l=o.ai(n)
o.d=o.d+(l.c-l.d)
k=l.a2()
q+=k.length
B.c.A(s,k)
if(b4.d.l()!==A.cv(c1.a(k),A.cv(new A.aJ(m),0)))throw A.f(A.n("Invalid "+m+" checksum"))}b6=new Uint8Array(q)
for(c0=s.length,j=0,i=0;i<s.length;s.length===c0||(0,A.a_)(s),++i){k=s[i]
J.kS(b6,j,k)
j+=k.length}}else{if(c2>=c1)throw A.f(A.n("Invalid Frame Number: "+c2))
if(!(c2<c1))return A.a(c0,c2)
h=c0[c2]
b8=h.b
b9=h.c
s=A.j([],u.h)
for(c0=h.y,q=0,p=0;p<c0.length;++p){c1=b4.d
c1===$&&A.d()
c1.d=c0[p]
n=c1.l()
c1=b4.d
c1.ah(4)
c1.d+=4
c1=b4.d
l=c1.ai(n-4)
c1.d=c1.d+(l.c-l.d)
k=l.a2()
q+=k.length
B.c.A(s,k)}b6=new Uint8Array(q)
for(c0=s.length,j=0,i=0;i<s.length;s.length===c0||(0,A.a_)(s),++i){k=s[i]
J.kS(b6,j,k)
j+=k.length}}c0=b7.d
g=1
if(!(c0===3))if(!(c0===0)){if(c0===4)c0=2
else c0=c0===6?4:3
g=c0}t=null
try{t=B.B.bP(b6)}catch(f){return b5}e=A.v(t,!0,b5,0)
b4.c=b4.b=0
d=b5
if(b7.d===3){c0=b7.w
if(c0!=null){c1=c0.length
c=c1/3|0
b=b7.x
o=b!=null
a=o?b.length:0
a0=o?4:3
d=new A.aW(new Uint8Array(c*a0),c,a0)
for(o=a0===4,p=0,a1=0;p<c;++p,a1+=3){if(o&&p<a){if(!(p<b.length))return A.a(b,p)
a2=b[p]}else a2=255
if(!(a1<c1))return A.a(c0,a1)
a3=c0[a1]
a4=a1+1
if(!(a4<c1))return A.a(c0,a4)
a4=c0[a4]
a5=a1+2
if(!(a5<c1))return A.a(c0,a5)
d.cG(p,a3,a4,c0[a5],a2)}}}if(b7.d===0&&b7.x!=null&&d==null&&b7.c<=8){b=b7.x
a6=b.length
c0=b7.c
c=B.a.W(1,c0)
c1=c*4
o=new Uint8Array(c1)
d=new A.aW(o,c,4)
if(c0===1)a7=255
else if(c0===2)a7=85
else{c0=c0===4?17:1
a7=c0}for(p=0;p<c;++p){a8=p*a7
d.cG(p,a8,a8,a8,255)}for(p=0;p<a6;p+=2){c0=b[p]
a3=p+1
if(!(a3<a6))return A.a(b,a3)
a9=(c0&255)<<8|b[a3]&255
if(a9<c){c0=a9*4+3
if(!(c0<c1))return A.a(o,c0)
o[c0]=0}}}c0=b7.c
if(c0===1)b0=B.w
else if(c0===2)b0=B.y
else{if(c0===4)c1=B.z
else c1=c0===16?B.l:B.f
b0=c1}c1=b7.d
if(c1===0&&b7.x!=null&&c0>8)g=4
b1=A.R(b5,b5,b0,0,B.j,b9,b5,0,c1===2&&b7.x!=null?4:g,d,B.f,b8,!1)
b2=b7.a
b3=b7.b
b7.a=b8
b7.b=b9
b4.e=0
if(b7.r!==0){c0=b9+7>>>3
b4.bZ(e,b1,0,0,8,8,b8+7>>>3,c0)
c1=b8+3
b4.bZ(e,b1,4,0,8,8,c1>>>3,c0)
c0=b9+3
b4.bZ(e,b1,0,4,4,8,c1>>>2,c0>>>3)
c1=b8+1
b4.bZ(e,b1,2,0,4,4,c1>>>2,c0>>>2)
c0=b9+1
b4.bZ(e,b1,0,2,2,4,c1>>>1,c0>>>2)
b4.bZ(e,b1,1,0,2,2,b8>>>1,c0>>>1)
b4.bZ(e,b1,0,1,1,2,b8,b9>>>1)}else b4.ig(e,b1)
b7.a=b2
b7.b=b3
c0=b7.at
if(c0!=null)b1.c=new A.bf(b7.Q,B.d3,c0)
b7=b7.ax
if(b7.a!==0)b1.iU(b7)
return b1},
aS(a,a0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=null
if(c.aP(u.D.a(a))==null)return b
t=c.a
s=t.cy
r=s.length
if(r===0){t=c.al(0)
t.toString
return t}for(r=u.g,q=b,p=q,o=0;o<t.CW;++o){if(!(o<s.length))return A.a(s,o)
a0=s[o]
n=c.al(o)
if(n==null)continue
if(p==null||q==null){p=n.eY(n.gc2())
m=a0.f
p.y=B.b.h((m===0||a0.r===0?0:m/a0.r)*1000)
q=p
continue}m=o-1
if(!(m>=0&&m<s.length))return A.a(s,m)
l=s[m]
k=n.a
j=k==null
i=j?b:k.a
if(i==null)i=0
h=q.a
g=h==null
f=g?b:h.a
if(i===(f==null?0:f)){k=j?b:k.b
if(k==null)k=0
j=g?b:h.b
k=k===(j==null?0:j)&&a0.d===0&&a0.e===0&&a0.x===B.bV}else k=!1
if(k){m=a0.f
n.y=B.b.h((m===0||a0.r===0?0:m/a0.r)*1000)
p.aZ(n)
q=n
continue}e=p.x
if(e===$)e=p.x=A.j([],r)
if(!(m<e.length))return A.a(e,m)
q=A.bz(e[m],!1,!1)
d=l.w
if(d===B.bX){m=l.d
k=l.e
j=t.z
if(j==null){j=new Uint8Array(4)
i=new A.bT(j)
j[0]=0
j[1]=0
j[2]=0
j[3]=0
j=i}A.mh(q,!1,j,m,m+l.b-1,k,k+l.c-1)}else if(d===B.bY&&o>1){m=o-2
e=p.x
if(e===$)e=p.x=A.j([],r)
if(!(m>=0&&m<e.length))return A.a(e,m)
k=l.d
j=l.e
i=l.b
h=l.c
q=A.kA(q,e[m],B.am,h,i,k,j,h,i,k,j)}m=a0.f
q.y=B.b.h((m===0||a0.r===0?0:m/a0.r)*1000)
m=a0.x===B.bW?B.am:B.a2
q=A.kA(q,n,m,b,b,a0.d,a0.e,b,b,b,b)
p.aZ(q)}return p},
bO(a){return this.aS(a,null)},
bZ(a3,a4,a5,a6,a7,a8,a9,b0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=this,a1=a0.a,a2=a1.d
if(a2===4)t=2
else if(a2===2)t=3
else{a2=a2===6?4:1
t=a2}s=t*a1.c
r=B.a.j(s+7,3)
q=B.a.j(s*a9+7,3)
p=A.j([null,null],u.ff)
o=A.j([0,0,0,0],u.t)
for(a1=a7>1,n=a7-a5,m=a6,l=0,k=0;l<b0;++l,m+=a8,++a0.e){a2=J.c(a3.a,a3.d++)
if(!(a2>=0&&a2<5))return A.a(B.ae,a2)
j=B.ae[a2]
i=a3.ai(q)
a3.d=a3.d+(i.c-i.d)
B.c.i(p,k,i.a2())
if(!(k>=0&&k<2))return A.a(p,k)
h=p[k]
k=1-k
g=p[k]
h.toString
a0.eF(j,r,h,g)
a0.c=a0.b=0
a2=h.length
f=new A.aa(h,0,Math.min(a2,a2),0,!0)
for(a2=n<=1,e=a5,d=0;d<a9;++d,e+=a7){a0.eA(f,o)
c=a4.a
c=c==null?null:c.L(e,m,null)
a0.dC(c==null?new A.G():c,o)
if(!a2||a1)for(b=0;b<a7;++b)for(c=m+b,a=0;a<n;++a)a0.dC(a4.ab(e+a,c),o)}}},
ig(a0,a1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=c.a,a=b.d
if(a===4)t=2
else if(a===2)t=3
else{a=a===6?4:1
t=a}s=t*b.c
r=b.a
q=b.b
p=B.a.j(r*s+7,3)
o=B.a.j(s+7,3)
n=A.P(p,0,!1,u.p)
m=A.j([n,n],u.S)
l=A.j([0,0,0,0],u.t)
b=a1.a
k=b.gI(b)
k.F()
for(j=0,i=0;j<q;++j,i=f){b=J.c(a0.a,a0.d++)
if(!(b>=0&&b<5))return A.a(B.ae,b)
h=B.ae[b]
g=a0.ai(p)
a0.d=a0.d+(g.c-g.d)
B.c.i(m,i,g.a2())
if(!(i>=0&&i<2))return A.a(m,i)
f=1-i
c.eF(h,o,m[i],m[f])
c.c=c.b=0
b=m[i]
a=b.length
e=new A.aa(b,0,Math.min(a,a),0,!0)
for(d=0;d<r;++d){c.eA(e,l)
c.dC(k.gM(),l)
k.F()}}},
eF(a,b,c,d){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f
u.L.a(c)
u.T.a(d)
t=c.length
switch(a.a){case 0:break
case 1:for(s=J.aI(c),r=b;r<t;++r){q=c.length
if(!(r<q))return A.a(c,r)
p=c[r]
o=r-b
if(!(o>=0&&o<q))return A.a(c,o)
s.i(c,r,p+c[o]&255)}break
case 2:for(s=J.aI(c),q=d!=null,r=0;r<t;++r){if(q){if(!(r<d.length))return A.a(d,r)
n=d[r]}else n=0
if(!(r<c.length))return A.a(c,r)
s.i(c,r,c[r]+n&255)}break
case 3:for(s=J.aI(c),q=d!=null,r=0;r<t;++r){if(r<b)m=0
else{p=r-b
if(!(p>=0&&p<c.length))return A.a(c,p)
m=c[p]}if(q){if(!(r<d.length))return A.a(d,r)
n=d[r]}else n=0
if(!(r<c.length))return A.a(c,r)
s.i(c,r,c[r]+B.a.j(m+n,1)&255)}break
case 4:for(s=J.aI(c),q=d==null,p=!q,r=0;r<t;++r){o=r<b
if(o)m=0
else{l=r-b
if(!(l>=0&&l<c.length))return A.a(c,l)
m=c[l]}if(p){if(!(r<d.length))return A.a(d,r)
n=d[r]}else n=0
if(o||q)k=0
else{o=r-b
if(!(o>=0&&o<d.length))return A.a(d,o)
k=d[o]}j=m+n-k
i=Math.abs(j-m)
h=Math.abs(j-n)
g=Math.abs(j-k)
if(i<=h&&i<=g)f=m
else f=h<=g?n:k
if(!(r<c.length))return A.a(c,r)
s.i(c,r,c[r]+f&255)}break}},
bl(a,b){var t,s,r,q,p,o=this
if(b===0)return 0
if(b===8)return a.G()
if(b===16)return a.m()
for(t=a.c;s=o.c,s<b;){s=a.d
if(s>=t)throw A.f(A.n("Invalid PNG data."))
r=a.a
a.d=s+1
q=J.c(r,s)
s=o.c
o.b=B.a.W(q,s)
o.c=s+8}if(b===1)p=1
else if(b===2)p=3
else{if(b===4)t=15
else t=0
p=t}t=s-b
s=B.a.a0(o.b,t)
o.c=t
return s&p},
eA(a,b){var t,s,r=this
u.L.a(b)
t=r.a
s=t.d
switch(s){case 0:B.c.i(b,0,r.bl(a,t.c))
return
case 2:B.c.i(b,0,r.bl(a,t.c))
B.c.i(b,1,r.bl(a,t.c))
B.c.i(b,2,r.bl(a,t.c))
return
case 3:B.c.i(b,0,r.bl(a,t.c))
return
case 4:B.c.i(b,0,r.bl(a,t.c))
B.c.i(b,1,r.bl(a,t.c))
return
case 6:B.c.i(b,0,r.bl(a,t.c))
B.c.i(b,1,r.bl(a,t.c))
B.c.i(b,2,r.bl(a,t.c))
B.c.i(b,3,r.bl(a,t.c))
return}throw A.f(A.n("Invalid color type: "+s+"."))},
dC(a,b){var t,s,r,q,p,o,n,m,l,k
u.L.a(b)
t=this.a
s=t.d
switch(s){case 0:s=t.x
if(s!=null&&t.c>8){t=s.length
if(0>=t)return A.a(s,0)
r=s[0]
if(1>=t)return A.a(s,1)
s=s[1]
q=b[0]
a.a8(q,q,q,q!==((r&255)<<24|s&255)>>>0?a.gE():0)
return}a.am(b[0],0,0)
return
case 2:p=b[0]
q=b[1]
o=b[2]
t=t.x
if(t!=null){s=t.length
if(0>=s)return A.a(t,0)
r=t[0]
if(1>=s)return A.a(t,1)
n=t[1]
if(2>=s)return A.a(t,2)
m=t[2]
if(3>=s)return A.a(t,3)
l=t[3]
if(4>=s)return A.a(t,4)
k=t[4]
if(5>=s)return A.a(t,5)
t=t[5]
if(p!==((r&255)<<8|n&255)||q!==((m&255)<<8|l&255)||o!==((k&255)<<8|t&255)){a.a8(p,q,o,a.gE())
return}}a.am(p,q,o)
return
case 3:a.sN(b[0])
return
case 4:a.am(b[0],b[1],0)
return
case 6:a.a8(b[0],b[1],b[2],b[3])
return}throw A.f(A.n("Invalid color type: "+s+"."))}}
A.bE.prototype={
ad(){return"PnmFormat."+this.b}}
A.bF.prototype={}
A.i6.prototype={
bm(a){var t
this.b=A.v(a,!1,null,0)
t=this.cU()
if(t==="P1"||t==="P2"||t==="P5"||t==="P3"||t==="P6")return!0
return!1},
aS(a,b){if(this.aP(a)==null)return null
return this.al(0)},
aP(a){var t,s,r=this
r.b=A.v(a,!1,null,0)
t=r.cU()
if(t==="P1"){s=r.a=new A.bF(B.Z)
s.e=B.bZ}else if(t==="P2"){s=r.a=new A.bF(B.Z)
s.e=B.c_}else if(t==="P5"){s=r.a=new A.bF(B.Z)
s.e=B.aC}else if(t==="P3"){s=r.a=new A.bF(B.Z)
s.e=B.c0}else if(t==="P6"){s=r.a=new A.bF(B.Z)
s.e=B.aD}else return r.b=null
s.a=r.ci()
s=r.a
s.toString
s.b=r.ci()
s=r.a
if(s.a===0||s.b===0)return r.a=r.b=null
return s},
al(a){var t,s,r,q,p,o=this,n=null,m=o.a
if(m==null)return n
t=m.e
if(t===B.bZ){t=m.a
s=A.R(n,n,B.w,0,B.j,m.b,n,0,1,n,B.f,t,!1)
for(m=s.a,m=m.gI(m);m.F();){r=m.gM()
if(o.cU()==="1")r.am(1,1,1)
else r.am(0,0,0)}return s}else if(t===B.c_||t===B.aC){q=o.ci()
if(q===0)return n
m=o.a
t=m.a
m=m.b
s=A.R(n,n,o.f3(q),0,B.j,m,n,0,1,n,B.f,t,!1)
for(m=s.a,m=m.gI(m);m.F();){r=m.gM()
p=o.cX(o.a.e,q)
r.am(p,p,p)}return s}else if(t===B.c0||t===B.aD){q=o.ci()
if(q===0)return n
m=o.a
t=m.a
m=m.b
s=A.R(n,n,o.f3(q),0,B.j,m,n,0,3,n,B.f,t,!1)
for(m=s.a,m=m.gI(m);m.F();)m.gM().am(o.cX(o.a.e,q),o.cX(o.a.e,q),o.cX(o.a.e,q))
return s}return n},
f3(a){if(a>255)return B.l
if(a>15)return B.f
if(a>3)return B.z
if(a>1)return B.y
return B.w},
cX(a,b){if(a===B.aC||a===B.aD)return this.b.G()
return this.ci()},
ci(){var t,s,r=this.cU()
if(J.ao(r)===0)return 0
try{t=A.qc(r)
return t}catch(s){return 0}},
cU(){var t,s,r,q,p=this.b
if(p==null)return""
t=this.c
if(t.length!==0)return B.c.fd(t,0)
s=B.p.fi(p.js())
if(s.length===0)return""
while(B.p.dR(s,"#"))s=B.p.fi(this.b.fc(70))
p=u.cc
r=A.q(new A.bs(A.j(s.split(" "),u.s),u.bB.a(new A.i7()),p),p.v("e.E"))
for(p=r.length,q=0;q<p;++q)if(B.p.dR(r[q],"#")){B.c.st(r,q)
break}B.c.bD(t,r)
if(t.length===0)return""
return B.c.fd(t,0)}}
A.i7.prototype={
$1(a){return A.b0(a)!==""},
$S:28}
A.fM.prototype={
sje(a){u.T.a(a)},
sfu(a){u.T.a(a)},
sju(a){u.T.a(a)},
sjv(a){u.T.a(a)}}
A.fN.prototype={
sbE(a){u.T.a(a)},
sbH(a){u.T.a(a)}}
A.b4.prototype={}
A.fQ.prototype={
sbE(a){u.T.a(a)},
sbH(a){u.T.a(a)}}
A.fR.prototype={
sbE(a){u.T.a(a)},
sbH(a){u.T.a(a)}}
A.fU.prototype={
sbE(a){u.T.a(a)},
sbH(a){u.T.a(a)}}
A.fV.prototype={
sbE(a){u.T.a(a)},
sbH(a){u.T.a(a)}}
A.ej.prototype={}
A.fT.prototype={}
A.i8.prototype={
fT(a){var t,s,r,q,p=this
a.m()
a.m()
a.m()
a.m()
t=B.a.Y(a.c-a.d,8)
if(t>0){p.e=new Uint16Array(t)
p.f=new Uint16Array(t)
p.r=new Uint16Array(t)
p.w=new Uint16Array(t)
for(s=0;s<t;++s){r=p.e
q=a.m()
r.$flags&2&&A.b(r)
if(!(s<r.length))return A.a(r,s)
r[s]=q
q=p.f
r=a.m()
q.$flags&2&&A.b(q)
if(!(s<q.length))return A.a(q,s)
q[s]=r
r=p.r
q=a.m()
r.$flags&2&&A.b(r)
if(!(s<r.length))return A.a(r,s)
r[s]=q
q=p.w
r=a.m()
q.$flags&2&&A.b(q)
if(!(s<q.length))return A.a(q,s)
q[s]=r}}}}
A.cl.prototype={
fb(a,b,c,d,e,f,g){if(a.c-a.d<2)return
if(e==null)e=a.m()
switch(e){case 0:d.toString
this.iE(a,b,c,d)
break
case 1:if(f==null)f=this.iB(a,c)
d.toString
this.iD(a,b,c,d,f,g)
break
default:throw A.f(A.n("Unsupported compression: "+e))}},
jr(a,b,c,d){return this.fb(a,b,c,d,null,null,0)},
iB(a,b){var t,s,r=new Uint16Array(b)
for(t=0;t<b;++t){s=a.m()
if(!(t<b))return A.a(r,t)
r[t]=s}return r},
iE(a,b,c,d){var t,s=b*c
if(d===16)s*=2
if(s>a.c-a.d){t=new Uint8Array(s)
this.c=t
B.e.aB(t,0,s,255)
return}this.c=a.ag(s).a2()},
iD(a,b,c,d,e,f){var t,s,r,q,p,o,n,m=b*c
if(d===16)m*=2
t=new Uint8Array(m)
this.c=t
s=f*c
r=e.length
if(s>=r){B.e.aB(t,0,m,255)
return}for(q=0,p=0;p<c;++p,s=o){o=s+1
if(!(s>=0&&s<r))return A.a(e,s)
n=a.ai(e[s])
a.d=a.d+(n.c-n.d)
t=this.c
t.toString
this.hv(n,t,q)
q+=b}},
hv(a,b,c){var t,s,r,q,p,o,n,m
for(t=a.c,s=b.length;r=a.d,r<t;){q=a.a
a.d=r+1
r=J.c(q,r)
q=$.an()
q.$flags&2&&A.b(q)
q[0]=r
r=$.av()
if(0>=r.length)return A.a(r,0)
p=r[0]
if(p<0){p=1-p
r=a.d
if(r>=t)break
q=a.a
a.d=r+1
o=J.c(q,r)
if(c+p>s)p=s-c
for(r=b.$flags|0,n=0;n<p;++n,c=m){m=c+1
r&2&&A.b(b)
if(!(c>=0&&c<s))return A.a(b,c)
b[c]=o}}else{++p
if(c+p>s)p=s-c
p=Math.min(p,t-a.d)
for(n=0;n<p;++n,c=m){m=c+1
r=J.c(a.a,a.d++)
b.$flags&2&&A.b(b)
if(!(c>=0&&c<s))return A.a(b,c)
b[c]=r}}}}}
A.aY.prototype={
ad(){return"PsdColorMode."+this.b}}
A.fO.prototype={
fU(a){var t,s,r=this
r.as=A.v(a,!0,null,0)
r.ij()
if(r.c!==943870035)return
t=r.as.l()
r.as.ag(t)
t=r.as.l()
r.at=r.as.ag(t)
t=r.as.l()
r.ax=r.as.ag(t)
s=r.as
r.ay=s.ag(s.c-s.d)},
bF(){var t,s=this
if(s.c===943870035){t=s.as
t===$&&A.d()
t=t==null}else t=!0
if(t)return!1
s.iz()
s.iA()
s.iC()
s.ay=s.ax=s.at=s.as=null
return!0},
f1(){if(!this.bF())return null
return this.jw()},
jw(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a=this,a0=null,a1=a.y
if(a1!=null)return a1
a1=a.a
a1=A.R(a0,a0,B.f,0,B.j,a.b,a0,0,4,a0,B.f,a1,!1)
a.y=a1
a1.dE(0)
for(a1=a.w,t=0;t<a1.length;++t){s=a1[t]
r=s.y
r===$&&A.d()
if((r&2)!==0)continue
r=s.w
r===$&&A.d()
q=r/255
p=s.r
o=s.cx
r=s.a
r.toString
n=r
m=0
for(;;){r=s.f
r===$&&A.d()
if(!(m<r))break
r=s.a
r.toString
l=r+m
k=s.b
r=n>=0
j=0
for(;;){i=s.e
i===$&&A.d()
if(!(j<i))break
i=o.a
h=i==null?a0:i.L(j,m,a0)
if(h==null)h=new A.G()
g=B.b.h(h.gn())
f=B.b.h(h.gp())
e=B.b.h(h.gq())
d=B.b.h(h.gu())
k.toString
if(k>=0&&k<a.a&&r&&n<a.b){i=s.b
i.toString
c=a.y.a
b=c==null?a0:c.L(i+j,l,a0)
if(b==null)b=new A.G()
a.h0(B.b.h(b.gn()),B.b.h(b.gp()),B.b.h(b.gq()),B.b.h(b.gu()),g,f,e,d,p,q,b)}++j;++k}++m;++n}}a1=a.y
a1.toString
return a1},
h0(a,b,c,d,e,f,g,h,i,j,k){var t,s,r,q,p,o=h/255*j
switch(i){case 1885434739:t=d
s=c
r=b
q=a
break
case 1852797549:t=h
s=g
r=f
q=e
break
case 1684632435:t=h
s=g
r=f
q=e
break
case 1684107883:q=Math.min(a,e)
r=Math.min(b,f)
s=Math.min(c,g)
t=h
break
case 1836411936:q=B.a.j(a*e,8)
r=B.a.j(b*f,8)
s=B.a.j(c*g,8)
t=h
break
case 1768188278:q=A.ia(a,e)
r=A.ia(b,f)
s=A.ia(c,g)
t=h
break
case 1818391150:q=A.ic(a,e)
r=A.ic(b,f)
s=A.ic(c,g)
t=h
break
case 1684751212:t=h
s=g
r=f
q=e
break
case 1818850405:q=Math.max(a,e)
r=Math.max(b,f)
s=Math.max(c,g)
t=h
break
case 1935897198:q=A.ki(a,e)
r=A.ki(b,f)
s=A.ki(c,g)
t=h
break
case 1684633120:q=A.ib(a,e)
r=A.ib(b,f)
s=A.ib(c,g)
t=h
break
case 1818518631:q=e+a>255?255:a+e
r=f+b>255?255:b+f
s=g+c>255?255:c+g
t=h
break
case 1818706796:t=h
s=g
r=f
q=e
break
case 1870030194:q=A.kg(a,e,d,h)
r=A.kg(b,f,d,h)
s=A.kg(c,g,d,h)
t=h
break
case 1934387572:q=A.kj(a,e)
r=A.kj(b,f)
s=A.kj(c,g)
t=h
break
case 1749838196:q=A.ke(a,e)
r=A.ke(b,f)
s=A.ke(c,g)
t=h
break
case 1984719220:q=A.kk(a,e)
r=A.kk(b,f)
s=A.kk(c,g)
t=h
break
case 1816947060:q=A.kf(a,e)
r=A.kf(b,f)
s=A.kf(c,g)
t=h
break
case 1884055924:q=A.kh(a,e)
r=A.kh(b,f)
s=A.kh(c,g)
t=h
break
case 1749903736:q=e<255-a?0:255
r=f<255-b?0:255
s=g<255-c?0:255
t=h
break
case 1684629094:q=Math.abs(e-a)
r=Math.abs(f-b)
s=Math.abs(g-c)
t=h
break
case 1936553316:q=A.kd(a,e)
r=A.kd(b,f)
s=A.kd(c,g)
t=h
break
case 1718842722:t=h
s=g
r=f
q=e
break
case 1717856630:t=h
s=g
r=f
q=e
break
case 1752524064:t=h
s=g
r=f
q=e
break
case 1935766560:t=h
s=g
r=f
q=e
break
case 1668246642:t=h
s=g
r=f
q=e
break
case 1819634976:t=h
s=g
r=f
q=e
break
default:t=h
s=g
r=f
q=e}p=1-o
k.sn(B.b.h(a*p+q*o))
k.sp(B.b.h(b*p+r*o))
k.sq(B.b.h(c*p+s*o))
k.su(B.b.h(d*p+t*o))},
ij(){var t,s,r=this,q=r.as
q===$&&A.d()
r.c=q.l()
q=r.as.m()
r.d=q
if(q!==1){r.c=0
return}t=r.as.ag(6)
for(s=0;s<6;++s)if(J.c(t.a,t.d+s)!==0){r.c=0
return}r.e=r.as.m()
r.b=r.as.l()
r.a=r.as.l()
r.f=r.as.m()
q=r.as.m()
if(!(q<8))return A.a(B.bQ,q)
r.r=B.bQ[q]},
iz(){var t,s,r,q,p,o,n=this,m=n.at
m.d=m.b
for(m=n.z;t=n.at,t.d<t.c;){s=t.l()
r=n.at.m()
t=n.at
q=J.c(t.a,t.d++)
n.at.ah(q)
if((q&1)===0)++n.at.d
q=n.at.l()
t=n.at
p=t.ai(q)
o=t.d+(p.c-p.d)
t.d=o
if((q&1)===1)t.d=o+1
if(s===943868237)m.i(0,r,new A.fP())}},
iA(){var t,s,r,q,p,o,n,m,l,k,j=this,i=j.ax
i.d=i.b
t=i.l()
if((t&1)!==0)++t
s=j.ax.ag(t)
i=j.w
B.c.dE(i)
if(t>0){r=s.m()
q=$.am()
q.$flags&2&&A.b(q)
q[0]=r
r=$.au()
if(0>=r.length)return A.a(r,0)
p=r[0]
if(p<0)p=-p
for(r=u.N,q=u.ha,o=u.l,n=u.af,m=0;m<p;++m){l=new A.fS(A.D(r,q),A.j([],o),A.j([],n))
l.fV(s)
B.c.A(i,l)}}for(m=0;m<i.length;++m)i[m].jo(s,j)
t=j.ax.l()
k=j.ax.ag(t)
if(t>0){k.m()
k.m()
k.m()
k.m()
k.m()
k.m()
k.G()}},
iC(){var t,s,r,q,p,o,n=this,m=n.ay
m.d=m.b
t=m.m()
if(t===1){m=n.b
s=n.e
s===$&&A.d()
r=m*s
q=new Uint16Array(r)
for(p=0;p<r;++p)q[p]=n.ay.m()}else q=null
n.x=u.x.a(A.j([],u._))
p=0
for(;;){m=n.e
m===$&&A.d()
if(!(p<m))break
m=n.x
s=n.ay
s.toString
o=p===3?-1:p
o=new A.cl(o)
o.fb(s,n.a,n.b,n.f,t,q,p)
B.c.A(m,o);++p}n.y=A.lD(n.r,n.f,n.a,n.b,n.x)},
$iJ:1}
A.fP.prototype={}
A.fS.prototype={
fV(a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=this,a1=a3.l(),a2=$.K()
a2.$flags&2&&A.b(a2)
a2[0]=a1
a1=$.a4()
if(0>=a1.length)return A.a(a1,0)
a0.a=a1[0]
a2[0]=a3.l()
a0.b=a1[0]
a2[0]=a3.l()
a0.c=a1[0]
a2[0]=a3.l()
a1=a1[0]
a0.d=a1
a2=a0.b
a2.toString
a0.e=a1-a2
a2=a0.c
a1=a0.a
a1.toString
a0.f=a2-a1
a0.as=u.x.a(A.j([],u._))
t=a3.m()
for(s=0;s<t;++s){a1=a3.m()
a2=$.am()
a2.$flags&2&&A.b(a2)
a2[0]=a1
a1=$.au()
if(0>=a1.length)return A.a(a1,0)
r=a1[0]
a3.l()
B.c.A(a0.as,new A.cl(r))}q=a3.l()
if(q!==943868237)throw A.f(A.n("Invalid PSD layer signature: "+B.a.d7(q,16)))
a0.r=a3.l()
a0.w=a3.G()
a3.G()
a0.y=a3.G()
if(a3.G()!==0)throw A.f(A.n("Invalid PSD layer data"))
p=a3.l()
o=a3.ag(p)
if(p>0){p=o.l()
if(p>0){n=o.ag(p)
a1=n.d
n.l()
n.l()
n.l()
n.l()
n.G()
n.G()
if(n.c-a1===20)n.d+=2
else{n.G()
n.G()
n.l()
n.l()
n.l()
n.l()}}p=o.l()
if(p>0)new A.i8().fT(o.ag(p))
p=o.G()
o.ah(p)
m=4-B.a.a1(p,4)-1
if(m>0)o.d+=m
for(a1=o.c,a2=a0.ay,l=a0.cy,k=u.t,j=u.g0;o.d<a1;){q=o.l()
if(q!==943868237)throw A.f(A.n("PSD invalid signature for layer additional data: "+B.a.d7(q,16)))
i=o.ah(4)
p=o.l()
h=o.ai(p)
g=o.d+(h.c-h.d)
o.d=g
if((p&1)===1)o.d=g+1
a2.i(0,i,A.nH(i,h))
if(i==="lrFX"){f=A.o(j.a(a2.k(0,"lrFX")).b,null,0)
f.m()
e=f.m()
for(d=0;d<e;++d){f.ah(4)
c=f.ah(4)
b=f.l()
if(c==="dsdw"){a=new A.fN()
B.c.A(l,a)
a.a=f.l()
f.l()
f.l()
f.l()
f.l()
a.sbE(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
f.ah(8)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
a.sbH(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}else if(c==="isdw"){a=new A.fR()
B.c.A(l,a)
a.a=f.l()
f.l()
f.l()
f.l()
f.l()
a.sbE(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
f.ah(8)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
a.sbH(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}else if(c==="oglw"){a=new A.fU()
B.c.A(l,a)
a.a=f.l()
f.l()
f.l()
a.sbE(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
f.ah(8)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
if(a.a===2)a.sbH(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}else if(c==="iglw"){a=new A.fQ()
B.c.A(l,a)
a.a=f.l()
f.l()
f.l()
a.sbE(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
f.ah(8)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
if(a.a===2){J.c(f.a,f.d++)
a.sbH(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}}else if(c==="bevl"){a=new A.fM()
B.c.A(l,a)
a.a=f.l()
f.l()
f.l()
f.l()
f.ah(8)
f.ah(8)
a.sje(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
a.sfu(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
J.c(f.a,f.d++)
if(a.a===2){a.sju(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
a.sjv(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}}else if(c==="sofi"){a=new A.fV()
B.c.A(l,a)
a.a=f.l()
f.ah(4)
a.sbE(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))
J.c(f.a,f.d++)
J.c(f.a,f.d++)
a.sbH(A.j([f.m(),f.m(),f.m(),f.m(),f.m()],k))}else f.d+=b}}}}},
jo(a,b){var t,s,r,q,p,o=this,n=0
for(;;){t=o.as
t===$&&A.d()
if(!(n<t.length))break
t=t[n]
s=o.e
s===$&&A.d()
r=o.f
r===$&&A.d()
t.jr(a,s,r,b.f);++n}s=b.r
r=b.f
q=o.e
q===$&&A.d()
p=o.f
p===$&&A.d()
o.cx=A.lD(s,r,q,p,t)}}
A.d3.prototype={}
A.i9.prototype={
aS(a,b){var t,s,r,q=null,p=A.lC(a)
this.a=p
t=1
if(t===1){p=p.f1()
return p}for(s=q,r=0;r<t;++r){p=this.a
b=p==null?q:p.f1()
if(b==null)continue
if(s==null){b.w=B.aU
s=b}else s.aZ(b)}return s}}
A.fW.prototype={}
A.d6.prototype={}
A.ar.prototype={
b3(a,b){var t=this
return new A.ar(t.a+b.a,t.b+b.b,t.c+b.c,t.d+b.d)}}
A.d4.prototype={$iJ:1,
gV(){return this.b}}
A.d5.prototype={$iJ:1,
gV(){return this.f}}
A.ek.prototype={$iJ:1,
gV(){return this.b}}
A.aO.prototype={
sck(a){var t=this.a,s=this.b+1
t.$flags&2&&A.b(t)
if(!(s<t.length))return A.a(t,s)
t[s]=a},
cB(){var t,s=this.e,r=this.d
if(s){t=r>>>9
if(!(t<32))return A.a(B.q,t)
return new A.d6(B.q[t],B.q[r>>>4&31],B.v[r&15])}else return new A.d6(B.v[r>>>7&15],B.v[r>>>3&15],B.ag[r&7])},
cD(){var t,s=this.e,r=this.d
if(s){t=r>>>9
if(!(t<32))return A.a(B.q,t)
return new A.ar(B.q[t],B.q[r>>>4&31],B.v[r&15],255)}else return new A.ar(B.v[r>>>7&15],B.v[r>>>3&15],B.ag[r&7],B.ag[r>>>11&7])},
cC(){var t,s=this.r,r=this.f
if(s){t=r>>>10
if(!(t<32))return A.a(B.q,t)
return new A.d6(B.q[t],B.q[r>>>5&31],B.q[r&31])}else return new A.d6(B.v[r>>>8&15],B.v[r>>>4&15],B.v[r&15])},
cE(){var t,s=this.r,r=this.f
if(s){t=r>>>10
if(!(t<32))return A.a(B.q,t)
return new A.ar(B.q[t],B.q[r>>>5&31],B.q[r&31],255)}else return new A.ar(B.v[r>>>8&15],B.v[r>>>4&15],B.v[r&15],B.ag[r>>>12&7])},
ce(){var t=this,s=t.c?1:0,r=t.d,q=t.e?1:0,p=t.f,o=t.r?1:0
return(s|(r&16383)<<1|q<<15|(p&32767)<<16|o<<31)>>>0},
bu(){var t,s=this,r=s.a,q=s.b+1
if(!(q<r.length))return A.a(r,q)
t=r[q]
s.c=(t&1)===1
s.sck(s.ce())
s.d=t>>>1&16383
s.sck(s.ce())
s.e=(t>>>15&1)===1
s.sck(s.ce())
s.f=t>>>16&32767
s.sck(s.ce())
s.r=(t>>>31&1)===1
s.sck(s.ce())}}
A.id.prototype={
aP(a){var t,s=this,r=a.length,q=r-(r>>>1&1431655765)>>>0
q=(q&858993459)+(q>>>2&858993459)
if((q+(q>>>4)>>>0&252645135)*16843009>>>0>>>24===1){t=s.hh(a)
if(t!=null){s.a=a
return s.b=t}}t=s.hu(a)
if(t!=null){s.a=a
return s.b=t}t=s.hs(a)
if(t!=null){s.a=a
return s.b=t}return null},
hu(a){var t,s,r=A.v(a,!1,null,0)
if(r.l()!==52)return null
if(r.l()!==55727696)return null
t=A.j([0,0,0,0],u.t)
s=new A.d5(t)
r.l()
s.b=r.l()
B.c.i(t,0,r.G())
B.c.i(t,1,r.G())
B.c.i(t,2,r.G())
B.c.i(t,3,r.G())
r.l()
r.l()
s.f=r.l()
s.r=r.l()
r.l()
r.l()
r.l()
r.l()
s.Q=r.l()
return s},
hs(a){var t,s,r=A.v(a,!1,null,0)
if(r.l()!==52)return null
t=new A.d4()
t.b=r.l()
t.a=r.l()
r.l()
t.d=r.l()
r.l()
t.f=r.l()
r.l()
r.l()
r.l()
t.y=r.l()
s=r.l()
t.z=s
t.Q=r.l()
if(s!==559044176)return null
return t},
hh(a){var t,s,r,q,p,o,n=null,m=a.length,l=A.v(a,!1,n,0)
if(l.l()!==0)return n
t=new A.ek()
t.b=l.l()
t.a=l.l()
l.l()
l.l()
l.l()
l.l()
l.l()
l.l()
l.l()
s=l.l()
t.y=s
if(s===559044176)return n
r=0
q=8
if(!(m===32)){p=0
for(;;){if(!(p<10)){r=1
break}o=p<<1>>>0
if((B.a.O(64,o)&m)>>>0!==0){q=B.a.O(16,p)
r=1
break}if((B.a.O(128,o)&m)>>>0!==0){q=B.a.O(16,p)
break}++p}if(p===10)return n}if((r+1)*2===4)return n
t.b=t.a=q
return t},
al(a){var t,s,r=this,q=r.b
if(q==null||r.a==null)return null
if(q instanceof A.ek){q=q.a
t=r.b.gV()
s=r.a
s.toString
return r.dj(q,t,s)}else if(q instanceof A.d4){q=r.a
q.toString
return r.hr(q)}else if(q instanceof A.d5){q=r.a
q.toString
return r.ht(q)}return null},
aS(a,b){if(this.aP(a)==null)return null
return this.al(0)},
hr(a){var t,s,r,q,p,o,n,m,l,k,j,i,h=this,g=null,f=a.length
if(f<52||h.b==null)return g
t=h.b
t.toString
u.fi.a(t)
s=A.v(a,!1,g,0)
s.d+=52
r=t.Q
if(r<1)r=(t.d&4096)!==0?6:1
if(r!==1)return g
q=t.a
p=t.b
if(q*p*t.f/8>f-52)return g
switch(t.d&255){case 16:o=A.R(g,g,B.f,0,B.j,p,g,0,4,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
m=J.c(s.a,s.d++)
l=J.c(s.a,s.d++)
n.sn(l&240)
n.sp((l&15)<<4)
n.sq(m&240)
n.su((m&15)<<4)}return o
case 17:o=A.R(g,g,B.f,0,B.j,p,g,0,4,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
k=s.m()
j=(k&1)!==0?255:0
n.sn(k>>>8&248)
n.sp(k>>>3&248)
n.sq((k&62)<<2)
n.su(j)}return o
case 18:o=A.R(g,g,B.f,0,B.j,p,g,0,4,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
n.sn(J.c(s.a,s.d++))
n.sp(J.c(s.a,s.d++))
n.sq(J.c(s.a,s.d++))
n.su(J.c(s.a,s.d++))}return o
case 19:o=A.R(g,g,B.f,0,B.j,p,g,0,3,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
k=s.m()
n.sn(k>>>8&248)
n.sp(k>>>3&252)
n.sq((k&31)<<3)}return o
case 20:o=A.R(g,g,B.f,0,B.j,p,g,0,3,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
k=s.m()
n.sn((k&31)<<3)
n.sp(k>>>2&248)
n.sq(k>>>7&248)}return o
case 21:o=A.R(g,g,B.f,0,B.j,p,g,0,3,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
n.sn(J.c(s.a,s.d++))
n.sp(J.c(s.a,s.d++))
n.sq(J.c(s.a,s.d++))}return o
case 22:o=A.R(g,g,B.f,0,B.j,p,g,0,1,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();)t.gM().sn(J.c(s.a,s.d++))
return o
case 23:o=A.R(g,g,B.f,0,B.j,p,g,0,4,g,B.f,q,!1)
for(t=o.a,t=t.gI(t);t.F();){n=t.gM()
j=J.c(s.a,s.d++)
i=J.c(s.a,s.d++)
n.sn(i)
n.sp(i)
n.sq(i)
n.su(j)}return o
case 24:return g
case 25:return t.y===0?h.eb(q,p,s.a2()):h.dj(q,p,s.a2())}return g},
ht(a){var t,s=this.b
if(!(s instanceof A.d5))return null
t=A.v(a,!1,null,0)
t.d=(t.d+=52)+s.Q
if(s.c[0]===0)switch(s.b){case 2:return this.eb(s.r,s.f,t.a2())
case 3:return this.dj(s.r,s.f,t.a2())}return null},
eb(c5,c6,c7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5=null,b6=A.R(b5,b5,B.f,0,B.j,c6,b5,0,3,b5,B.f,c5,!1),b7=c5/4|0,b8=b7-1,b9=J.aw(B.e.gB(c7),0,null),c0=new A.aO(b9),c1=new A.aO(J.aw(B.e.gB(c7),0,null)),c2=new A.aO(J.aw(B.e.gB(c7),0,null)),c3=new A.aO(J.aw(B.e.gB(c7),0,null)),c4=new A.aO(J.aw(B.e.gB(c7),0,null))
for(t=b9.length,s=0,r=0;s<b7;++s,r+=4)for(q=0,p=0;q<b7;++q,p+=4){c0.b=A.bl(q,s)<<1>>>0
c0.bu()
o=c0.b
if(!(o<t))return A.a(b9,o)
n=b9[o]
m=c0.c?4:0
for(l=0,k=0;k<4;++k){j=(s+(k<2?-1:0)&b8)>>>0
i=(j+1&b8)>>>0
for(o=k+r,h=0;h<4;++h){g=(q+(h<2?-1:0)&b8)>>>0
f=(g+1&b8)>>>0
c1.b=A.bl(g,j)<<1>>>0
c1.bu()
c2.b=A.bl(f,j)<<1>>>0
c2.bu()
c3.b=A.bl(g,i)<<1>>>0
c3.bu()
c4.b=A.bl(f,i)<<1>>>0
c4.bu()
e=c1.cB()
if(!(l>=0&&l<16))return A.a(B.m,l)
d=B.m[l][0]
c=c2.cB()
b=B.m[l][1]
a=c3.cB()
a0=B.m[l][2]
a1=c4.cB()
a2=B.m[l][3]
a3=c1.cC()
a4=B.m[l][0]
a5=c2.cC()
a6=B.m[l][1]
a7=c3.cC()
a8=B.m[l][2]
a9=c4.cC()
b0=B.m[l][3]
b1=B.bD[m+n&3]
b2=b1[0]
b3=b1[1]
b4=b6.a
if(b4!=null)b4.a3(h+p,o,(e.a*d+c.a*b+a.a*a0+a1.a*a2)*b2+(a3.a*a4+a5.a*a6+a7.a*a8+a9.a*b0)*b3>>>7,(e.b*d+c.b*b+a.b*a0+a1.b*a2)*b2+(a3.b*a4+a5.b*a6+a7.b*a8+a9.b*b0)*b3>>>7,(e.c*d+c.c*b+a.c*a0+a1.c*a2)*b2+(a3.c*a4+a5.c*a6+a7.c*a8+a9.c*b0)*b3>>>7)
n=n>>>2;++l}}}return b6},
dj(b3,b4,b5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=null,a4=A.R(a3,a3,B.f,0,B.j,b4,a3,0,4,a3,B.f,b3,!1),a5=b3/4|0,a6=a5-1,a7=J.aw(B.e.gB(b5),0,null),a8=new A.aO(a7),a9=new A.aO(J.aw(B.e.gB(b5),0,null)),b0=new A.aO(J.aw(B.e.gB(b5),0,null)),b1=new A.aO(J.aw(B.e.gB(b5),0,null)),b2=new A.aO(J.aw(B.e.gB(b5),0,null))
for(t=a7.length,s=0,r=0;s<a5;++s,r+=4)for(q=0,p=0;q<a5;++q,p+=4){a8.b=A.bl(q,s)<<1>>>0
a8.bu()
o=a8.b
if(!(o<t))return A.a(a7,o)
n=a7[o]
m=a8.c?4:0
for(l=0,k=0;k<4;++k){j=(s+(k<2?-1:0)&a6)>>>0
i=(j+1&a6)>>>0
for(o=k+r,h=0;h<4;++h){g=(q+(h<2?-1:0)&a6)>>>0
f=(g+1&a6)>>>0
a9.b=A.bl(g,j)<<1>>>0
a9.bu()
b0.b=A.bl(f,j)<<1>>>0
b0.bu()
b1.b=A.bl(g,i)<<1>>>0
b1.bu()
b2.b=A.bl(f,i)<<1>>>0
b2.bu()
e=a9.cD()
if(!(l>=0&&l<16))return A.a(B.m,l)
d=B.m[l][0]
c=b0.cD()
b=B.m[l][1]
b=new A.ar(e.a*d,e.b*d,e.c*d,e.d*d).b3(0,new A.ar(c.a*b,c.b*b,c.c*b,c.d*b))
c=b1.cD()
d=B.m[l][2]
d=b.b3(0,new A.ar(c.a*d,c.b*d,c.c*d,c.d*d))
c=b2.cD()
b=B.m[l][3]
a=d.b3(0,new A.ar(c.a*b,c.b*b,c.c*b,c.d*b))
b=a9.cE()
c=B.m[l][0]
d=b0.cE()
e=B.m[l][1]
e=new A.ar(b.a*c,b.b*c,b.c*c,b.d*c).b3(0,new A.ar(d.a*e,d.b*e,d.c*e,d.d*e))
d=b1.cE()
c=B.m[l][2]
c=e.b3(0,new A.ar(d.a*c,d.b*c,d.c*c,d.d*c))
d=b2.cE()
e=B.m[l][3]
a0=c.b3(0,new A.ar(d.a*e,d.b*e,d.c*e,d.d*e))
a1=B.bD[m+n&3]
e=a1[0]
d=a1[1]
c=a1[2]
b=a1[3]
a2=a4.a
if(a2!=null)a2.ak(h+p,o,a.a*e+a0.a*d>>>7,a.b*e+a0.b*d>>>7,a.c*e+a0.c*d>>>7,a.d*c+a0.d*b>>>7)
n=n>>>2;++l}}}return a4}}
A.eq.prototype={
bS(a){var t,s,r=this
if(a.c-a.d<18)return
r.a=a.G()
r.b=a.G()
t=a.G()
if(t<12){if(!(t>=0))return A.a(B.bA,t)
s=B.bA[t]}else s=B.ak
r.c=s
a.m()
r.e=a.m()
r.f=a.G()
a.m()
a.m()
r.x=a.m()
r.y=a.m()
r.z=a.G()
r.Q=a.G()},
f6(){var t=this,s=t.z
if(s!==8&&s!==16&&s!==24&&s!==32)return!1
s=t.c
if(s===B.F||s===B.G){if(t.e>256||t.b!==1)return!1
s=t.f
if(s!==16&&s!==24&&s!==32)return!1}else if(t.b===1)return!1
return!0},
$iJ:1}
A.as.prototype={
ad(){return"TgaImageType."+this.b}}
A.ih.prototype={
aS(a,b){if(this.aP(a)==null)return null
return this.al(0)},
aP(a){var t,s,r,q,p=this
p.a=new A.eq(B.ak)
t=A.v(a,!1,null,0)
p.b=t
s=t.ag(18)
p.a.bS(s)
t=p.a
if(!t.f6())return null
r=p.b
r.d+=t.a
q=t.c
if(q===B.F||q===B.G)t.as=r.ag(t.e*B.a.j(t.f,3)).a2()
t=p.a
t.ax=p.b.d
return t},
al(a){var t=this,s=t.a
if(s==null)return null
s=s.c
if(s===B.c8)return t.ea()
else if(s===B.c7||s===B.G)return t.hw()
else if(s===B.F)return t.ea()
return null},
e6(a,b){var t,s,r,q,p,o,n,m=this,l=A.v(a,!1,null,0),k=m.a.f
if(k===16){k=m.b
k===$&&A.d()
t=k.m()
s=t>>>7&248
r=t>>>2&248
q=(t&31)<<3
p=(t&32768)!==0?0:255
for(o=0;o<m.a.e;++o){b.br(o,s)
b.bq(o,r)
b.bp(o,q)
b.bo(o,p)}}else{n=k===32
for(o=0;o<m.a.e;++o){q=J.c(l.a,l.d++)
r=J.c(l.a,l.d++)
s=J.c(l.a,l.d++)
p=n?J.c(l.a,l.d++):255
b.br(o,s)
b.bq(o,r)
b.bp(o,q)
b.bo(o,p)}}},
hw(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=this,e=null,d=f.a,c=d.z,b=c===16,a=b||c===32,a0=d.x,a1=d.y,a2=a?4:3
d=d.c
t=A.R(e,e,B.f,0,B.j,a1,e,0,a2,e,B.f,a0,d===B.F||d===B.G)
d=t.a
if((d==null?e:d.gR())!=null){d=f.a.as
d.toString
a0=t.a
a0=a0==null?e:a0.gR()
a0.toString
f.e6(d,a0)}s=t.ga5()
r=t.gV()-1
d=c===8
q=0
for(;;){a0=f.b
a0===$&&A.d()
a1=a0.d
if(!(a1<a0.c&&r>=0))break
a2=a0.a
a0.d=a1+1
p=J.c(a2,a1)
o=(p&127)+1
n=0
if((p&128)!==0)if(d){a0=f.b
m=J.c(a0.a,a0.d++)
for(l=0;l<o;++l){k=q+1
a0=t.a
if(a0!=null)a0.aC(q,r,m)
if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}}else{a0=f.b
if(b){j=a0.m()
m=j>>>7&248
i=j>>>2&248
h=(j&31)<<3
g=(j&32768)!==0?0:255
for(l=0;l<o;++l){k=q+1
a0=t.a
if(a0!=null)a0.ak(q,r,m,i,h,g)
if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}}else{h=J.c(a0.a,a0.d++)
a0=f.b
i=J.c(a0.a,a0.d++)
a0=f.b
m=J.c(a0.a,a0.d++)
if(a){a0=f.b
g=J.c(a0.a,a0.d++)}else g=255
for(l=0;l<o;++l){k=q+1
a0=t.a
if(a0!=null)a0.ak(q,r,m,i,h,g)
if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}}}else if(d)for(l=0;l<o;++l){a0=f.b
m=J.c(a0.a,a0.d++)
k=q+1
a0=t.a
if(a0!=null)a0.aC(q,r,m)
if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}else if(b)for(l=0;l<o;++l){j=f.b.m()
g=(j&32768)!==0?0:255
k=q+1
a0=t.a
if(a0!=null)a0.ak(q,r,j>>>7&248,j>>>2&248,(j&31)<<3,g)
a0=f.b
if(a0.d>=a0.c){q=k
break}if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}else for(l=0;l<o;++l){a0=f.b
h=J.c(a0.a,a0.d++)
a0=f.b
i=J.c(a0.a,a0.d++)
a0=f.b
m=J.c(a0.a,a0.d++)
if(a){a0=f.b
g=J.c(a0.a,a0.d++)}else g=255
k=q+1
a0=t.a
if(a0!=null)a0.ak(q,r,m,i,h,g)
if(k>=s){--r
if(r<0){q=n
break}q=0}else q=k}if(q>=s){--r
if(r<0)break
q=0}}return t},
ea(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e=this,d=null,c=e.b
c===$&&A.d()
t=e.a
c.d=t.ax
s=t.z
c=s===16
r=!0
if(!c)if(s!==32){q=t.c
if(q===B.F||q===B.G){q=t.f
q=q===16||q===32}else q=!1
r=q}q=t.x
p=t.y
o=r?4:3
t=t.c
n=A.R(d,d,B.f,0,B.j,p,d,0,o,d,B.f,q,t===B.F||t===B.G)
t=e.a
q=t.c
if(q===B.F||q===B.G){t=t.as
t.toString
q=n.a
q=q==null?d:q.gR()
q.toString
e.e6(t,q)}if(s===8)for(m=n.gV()-1;m>=0;--m){l=0
for(;;){c=n.a
c=c==null?d:c.a
if(!(l<(c==null?0:c)))break
c=e.b
k=J.c(c.a,c.d++)
c=n.a
if(c!=null)c.aC(l,m,k);++l}}else if(c)for(m=n.gV()-1;m>=0;--m){l=0
for(;;){c=n.a
c=c==null?d:c.a
if(!(l<(c==null?0:c)))break
j=e.b.m()
i=(j&32768)!==0?0:255
c=n.a
if(c!=null)c.ak(l,m,j>>>7&248,j>>>2&248,(j&31)<<3,i);++l}}else for(m=n.gV()-1;m>=0;--m){l=0
for(;;){c=n.a
c=c==null?d:c.a
if(!(l<(c==null?0:c)))break
c=e.b
h=J.c(c.a,c.d++)
c=e.b
g=J.c(c.a,c.d++)
c=e.b
f=J.c(c.a,c.d++)
if(r){c=e.b
i=J.c(c.a,c.d++)}else i=255
c=n.a
if(c!=null)c.ak(l,m,f,g,h,i);++l}}return n}}
A.ii.prototype={
af(a){var t,s,r,q,p,o=this
if(a===0)return 0
if(o.c===0){o.c=8
o.b=o.a.G()}for(t=o.a,s=0;r=o.c,a>r;){q=B.a.W(s,r)
p=o.b
if(!(r>=0&&r<9))return A.a(B.x,r)
s=q+(p&B.x[r])
a-=r
o.c=8
o.b=J.c(t.a,t.d++)}if(a>0){if(r===0){o.c=8
o.b=t.G()}t=B.a.W(s,a)
r=o.b
q=o.c-a
r=B.a.bs(r,q)
if(!(a<9))return A.a(B.x,a)
s=t+(r&B.x[a])
o.c=q}return s}}
A.h0.prototype={
D(a){var t=this,s=t.a,r=$.kM().k(0,s)
if(r!=null)return r.a+": "+t.b.D(0)+" "+t.c
return"<"+s+">: "+t.b.D(0)+" "+t.c},
be(){var t,s,r,q,p=this,o=p.e
if(o!=null)return o
o=p.f
o.d=p.d
t=p.c
s=p.b
if(s!==B.d){r=s.a
if(!(r<14))return A.a(B.t,r)
r=B.t[r]}else r=0
q=o.ag(t*r)
switch(s.a){case 1:return p.e=new A.bg(new Uint8Array(A.w(q.ag(t).a2())))
case 2:return p.e=new A.bZ(t===0?"":q.ah(t-1))
case 7:return p.e=new A.bg(new Uint8Array(A.w(q.ag(t).a2())))
case 3:return p.e=A.le(q,t)
case 4:return p.e=A.l9(q,t)
case 5:return p.e=A.la(q,t)
case 11:return p.e=A.lf(q,t)
case 12:return p.e=A.l8(q,t)
case 6:return p.e=new A.by(new Int8Array(A.w(J.jL(B.e.gB(q.a2()),0,t))))
case 8:return p.e=A.ld(q,t)
case 9:return p.e=A.lb(q,t)
case 10:return p.e=A.lc(q,t)
case 13:case 0:return null}}}
A.ik.prototype={
j0(a,b,c,d){var t,s,r,q=this
q.r=b
q.x=q.w=0
t=B.a.Y(q.a+7,8)
for(s=0,r=0;r<d;++r){q.dh(a,s,c)
s+=t}},
dh(a,b,c){var t,s,r,q,p,o,n,m,l=this
l.d=0
for(t=l.a,s=!0;c<t;){while(s){r=l.bM(10)
if(!(r<1024))return A.a(B.ac,r)
q=B.ac[r]
p=B.a.j(q,1)&15
if(p===12){r=(r<<2&12|l.aQ(2))>>>0
if(!(r<16))return A.a(B.E,r)
q=B.E[r]
o=B.a.j(q,1)
c+=B.a.j(q,4)&4095
l.az(4-(o&7))}else if(p===0)throw A.f(A.n("TIFFFaxDecoder0"))
else if(p===15)throw A.f(A.n("TIFFFaxDecoder1"))
else{c+=B.a.j(q,5)&2047
l.az(10-p)
if((q&1)===0){B.c.i(l.f,l.d++,c)
s=!1}}}if(c===t){if(l.z===2)if(l.w!==0){t=l.x
t.toString
l.x=t+1
l.w=0}break}while(!s){r=l.aQ(4)
if(!(r<16))return A.a(B.a6,r)
q=B.a6[r]
n=q>>>5&2047
m=!0
if(n===100){r=l.bM(9)
if(!(r<512))return A.a(B.a8,r)
q=B.a8[r]
p=B.a.j(q,1)&15
n=B.a.j(q,5)&2047
if(p===12){l.az(5)
r=l.aQ(4)
if(!(r<16))return A.a(B.E,r)
q=B.E[r]
o=B.a.j(q,1)
n=B.a.j(q,4)&4095
l.aY(a,b,c,n)
c+=n
l.az(4-(o&7))}else if(p===15)throw A.f(A.n("TIFFFaxDecoder2"))
else{l.aY(a,b,c,n)
c+=n
l.az(9-p)
if((q&1)===0){B.c.i(l.f,l.d++,c)
s=m}}}else{if(n===200){r=l.aQ(2)
if(!(r<4))return A.a(B.a5,r)
q=B.a5[r]
n=q>>>5&2047
l.aY(a,b,c,n)
c+=n
l.az(2-(q>>>1&15))
B.c.i(l.f,l.d++,c)}else{l.aY(a,b,c,n)
c+=n
l.az(4-(q>>>1&15))
B.c.i(l.f,l.d++,c)}s=m}}if(c===t){if(l.z===2)if(l.w!==0){t=l.x
t.toString
l.x=t+1
l.w=0}break}}B.c.i(l.f,l.d++,c)},
j1(a0,a1,a2,a3,a4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a=this
a.r=a1
a.z=3
a.x=a.w=0
t=a.a
s=B.a.Y(t+7,8)
r=A.P(2,null,!1,u.I)
a.at=a4&1
a.as=a4>>>2&1
if(a.ew()!==1)throw A.f(A.n("TIFFFaxDecoder3"))
a.dh(a0,0,a2)
for(q=s,p=1;p<a3;++p){if(a.ew()===0){o=a.e
a.e=a.f
a.f=o
a.y=0
n=a2
m=-1
l=!0
k=0
for(;;){n.toString
if(!(n<t))break
a.ej(m,l,r)
j=r[0]
i=r[1]
h=a.aQ(7)
if(!(h<128))return A.a(B.aa,h)
h=B.aa[h]&255
g=h>>>3&15
f=h&7
if(g===0){if(!l){i.toString
a.aY(a0,q,n,i-n)}a.az(7-f)
n=i
m=n}else if(g===1){a.az(7-f)
e=k+1
d=e+1
if(l){n+=a.cO()
B.c.i(a.f,k,n)
c=a.cN()
a.aY(a0,q,n,c)
n+=c
B.c.i(a.f,e,n)}else{c=a.cN()
a.aY(a0,q,n,c)
n+=c
B.c.i(a.f,k,n)
n+=a.cO()
B.c.i(a.f,e,n)}k=d
m=n}else{if(g<=8){j.toString
b=j+(g-5)
e=k+1
B.c.i(a.f,k,b)
l=!l
if(l)a.aY(a0,q,n,b-n)
a.az(7-f)}else throw A.f(A.n("TIFFFaxDecoder4"))
n=b
k=e
m=n}}B.c.i(a.f,k,n)
a.d=k+1}else a.dh(a0,q,a2)
q+=s}},
j5(a4,a5,a6,a7,a8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=this
a3.r=a5
a3.z=4
a3.x=a3.w=0
t=a3.a
s=B.a.Y(t+7,8)
r=A.P(2,null,!1,u.I)
q=a3.f
a3.d=0
a3.d=1
B.c.i(q,0,t)
B.c.i(q,a3.d++,t)
for(p=0,o=0;o<a7;++o){n=a3.e
a3.e=a3.f
a3.f=n
a3.y=0
m=a6
l=-1
k=!0
j=0
for(;;){m.toString
if(!(m<t))break
a3.ej(l,k,r)
i=r[0]
h=r[1]
g=a3.aQ(7)
if(!(g<128))return A.a(B.aa,g)
g=B.aa[g]&255
f=g>>>3&15
e=g&7
if(f===0){if(!k){h.toString
a3.aY(a4,p,m,h-m)}a3.az(7-e)
m=h
l=m}else if(f===1){a3.az(7-e)
d=j+1
c=d+1
if(k){m+=a3.cO()
B.c.i(n,j,m)
b=a3.cN()
a3.aY(a4,p,m,b)
m+=b
B.c.i(n,d,m)}else{b=a3.cN()
a3.aY(a4,p,m,b)
m+=b
B.c.i(n,j,m)
m+=a3.cO()
B.c.i(n,d,m)}j=c
l=m}else if(f<=8){i.toString
a=i+(f-5)
d=j+1
B.c.i(n,j,a)
k=!k
if(k)a3.aY(a4,p,m,a-m)
a3.az(7-e)
m=a
j=d
l=m}else if(f===11){if(a3.aQ(3)!==7)throw A.f(A.n("TIFFFaxDecoder5"))
for(a0=0,a1=!1;!a1;k=a2){while(a3.aQ(1)!==1)++a0
if(a0>5){a0-=6
if(!k&&a0>0){d=j+1
B.c.i(n,j,m)
j=d}m+=a0
if(a0>0)k=!0
a2=a3.aQ(1)===0
if(a2){if(!k){d=j+1
B.c.i(n,j,m)
j=d}}else if(k){d=j+1
B.c.i(n,j,m)
j=d}k=a2
a1=!0}a2=a0===5
if(a2){if(!k){d=j+1
B.c.i(n,j,m)
j=d}m+=a0}else{m+=a0
d=j+1
B.c.i(n,j,m)
a3.aY(a4,p,m,1);++m
j=d}}}else throw A.f(A.n("TIFFFaxDecoder5 "+f))}B.c.i(n,j,m)
a3.d=j+1
p+=s}},
cO(){var t,s,r,q,p,o,n=this
for(t=0,s=!0;s;){r=n.bM(10)
if(!(r<1024))return A.a(B.ac,r)
q=B.ac[r]
p=B.a.j(q,1)&15
if(p===12){r=(r<<2&12|n.aQ(2))>>>0
if(!(r<16))return A.a(B.E,r)
q=B.E[r]
o=B.a.j(q,1)
t+=B.a.j(q,4)&4095
n.az(4-(o&7))}else if(p===0)throw A.f(A.n("TIFFFaxDecoder0"))
else if(p===15)throw A.f(A.n("TIFFFaxDecoder1"))
else{t+=B.a.j(q,5)&2047
n.az(10-p)
if((q&1)===0)s=!1}}return t},
cN(){var t,s,r,q,p,o,n,m=this
for(t=0,s=!1;!s;){r=m.aQ(4)
if(!(r<16))return A.a(B.a6,r)
q=B.a6[r]
p=q>>>5&2047
if(p===100){r=m.bM(9)
if(!(r<512))return A.a(B.a8,r)
q=B.a8[r]
o=B.a.j(q,1)&15
n=B.a.j(q,5)
if(o===12){m.az(5)
r=m.aQ(4)
if(!(r<16))return A.a(B.E,r)
q=B.E[r]
n=B.a.j(q,1)
t+=B.a.j(q,4)&4095
m.az(4-(n&7))}else if(o===15)throw A.f(A.n("TIFFFaxDecoder2"))
else{t+=n&2047
m.az(9-o)
if((q&1)===0)s=!0}}else{if(p===200){r=m.aQ(2)
if(!(r<4))return A.a(B.a5,r)
q=B.a5[r]
t+=q>>>5&2047
m.az(2-(q>>>1&15))}else{t+=p
m.az(4-(q>>>1&15))}s=!0}}return t},
ew(){var t,s,r=this,q="TIFFFaxDecoder8",p=r.as
if(p===0){if(r.bM(12)!==1)throw A.f(A.n("TIFFFaxDecoder6"))}else if(p===1){p=r.w
p.toString
t=8-p
if(r.bM(t)!==0)throw A.f(A.n(q))
if(t<4)if(r.bM(8)!==0)throw A.f(A.n(q))
while(s=r.bM(8),s!==1)if(s!==0)throw A.f(A.n(q))}if(r.at===0)return 1
else return r.aQ(1)},
ej(a,b,c){var t,s,r,q,p,o,n=this
u.cP.a(c)
t=n.e
s=n.d
r=n.y
q=r>0?r-1:0
q=b?(q&4294967294)>>>0:(q|1)>>>0
for(r=t.length,p=q;p<s;p+=2){if(!(p<r))return A.a(t,p)
o=t[p]
o.toString
a.toString
if(o>a){n.y=p
B.c.i(c,0,o)
break}}o=p+1
if(o<s){if(!(o<r))return A.a(t,o)
B.c.i(c,1,t[o])}},
aY(a,b,c,d){var t,s,r,q,p,o=8*b+A.u(c),n=o+d,m=B.a.j(o,3),l=o&7
if(l>0){t=B.a.W(1,7-l)
s=J.c(a.a,a.d+m)
for(;;){if(!(t>0&&o<n))break
s=(s|t)>>>0
t=t>>>1;++o}a.i(0,m,s)}m=B.a.j(o,3)
for(r=n-7;o<r;m=q){q=m+1
J.x(a.a,a.d+m,255)
o+=8}while(o<n){m=B.a.j(o,3)
r=J.c(a.a,a.d+m)
p=B.a.W(1,7-(o&7))
J.x(a.a,a.d+m,(r|p)>>>0);++o}},
bM(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=this,f=g.r
f===$&&A.d()
t=f.d
s=f.c-t-1
r=g.x
q=g.c
p=0
o=0
if(q===1){r.toString
n=J.c(f.a,t+r)
if(!(r===s)){f=r+1
t=g.r
q=t.a
t=t.d
if(f===s)p=J.c(q,t+f)
else{p=J.c(q,t+f)
f=g.r
o=J.c(f.a,f.d+(r+2))}}}else if(q===2){r.toString
n=B.T[J.c(f.a,t+r)&255]
if(!(r===s)){f=r+1
t=g.r
q=t.a
t=t.d
if(f===s)p=B.T[J.c(q,t+f)&255]
else{p=B.T[J.c(q,t+f)&255]
f=g.r
o=B.T[J.c(f.a,f.d+(r+2))&255]}}}else throw A.f(A.n("TIFFFaxDecoder7"))
f=g.w
f.toString
m=8-f
l=a-m
if(l>8){k=l-8
j=8}else{j=l
k=0}f=g.x
f.toString
f=g.x=f+1
if(!(m>=0&&m<9))return A.a(B.x,m)
i=B.a.W(n&B.x[m],l)
if(!(j>=0))return A.a(B.R,j)
h=B.a.a0(p&B.R[j],8-j)
if(k!==0){h=B.a.W(h,k)
if(!(k<9))return A.a(B.R,k)
h|=B.a.a0(o&B.R[k],8-k)
g.x=f+1
g.w=k}else if(j===8){g.w=0
g.x=f+1}else g.w=j
return(i|h)>>>0},
aQ(a){var t,s,r,q,p,o,n,m,l,k,j=this,i=j.r
i===$&&A.d()
t=i.d
s=i.c-t-1
r=j.x
q=j.c
p=0
if(q===1){r.toString
o=J.c(i.a,t+r)
if(!(r===s)){i=j.r
p=J.c(i.a,i.d+(r+1))}}else if(q===2){r.toString
o=B.T[J.c(i.a,t+r)&255]
if(!(r===s)){i=j.r
p=B.T[J.c(i.a,i.d+(r+1))&255]}}else throw A.f(A.n("TIFFFaxDecoder7"))
i=j.w
i.toString
n=8-i
m=a-n
l=n-a
if(l>=0){if(!(n>=0&&n<9))return A.a(B.x,n)
k=B.a.a0(o&B.x[n],l)
i+=a
j.w=i
if(i===8){j.w=0
i=j.x
i.toString
j.x=i+1}}else{if(!(n>=0&&n<9))return A.a(B.x,n)
k=B.a.W(o&B.x[n],-l)
if(!(m>=0&&m<9))return A.a(B.R,m)
k=(k|B.a.a0(p&B.R[m],8-m))>>>0
i=j.x
i.toString
j.x=i+1
j.w=m}return k},
az(a){var t,s=this,r=s.w
r.toString
t=r-a
if(t<0){r=s.x
r.toString
s.x=r-1
s.w=8+t}else s.w=t}}
A.h1.prototype={
fW(a){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e=this,d=null,c=A.o(a,d,0),b=a.m()
for(t=e.a,s=0;s<b;++s){r=a.m()
q=a.m()
p=a.l()
if(q>13){a.d+=4
continue}o=B.bx[q]
if(p*B.t[q]>4)n=a.l()
else{n=a.d
a.d=n+4}m=new A.h0(r,o,p,n,c)
t.i(0,r,m)
if(r===256){l=m.be()
l=l==null?d:l.h(0)
e.b=l==null?0:l}else if(r===257){l=m.be()
l=l==null?d:l.h(0)
e.c=l==null?0:l}else if(r===262){k=m.be()
j=k==null?d:k.h(0)
if(j==null)j=17
if(j<17){if(!(j>=0))return A.a(B.br,j)
e.d=B.br[j]}else e.d=B.aG}else if(r===259){l=m.be()
l=l==null?d:l.h(0)
e.e=l==null?0:l}else if(r===258){l=m.be()
l=l==null?d:l.h(0)
e.f=l==null?0:l}else if(r===277){l=m.be()
l=l==null?d:l.h(0)
e.r=l==null?0:l}else if(r===317){l=m.be()
l=l==null?d:l.h(0)
e.Q=l==null?0:l}else if(r===339){l=m.be()
k=l==null?d:l.h(0)
if(k==null)k=0
if(!(k>=0&&k<4))return A.a(B.bv,k)
e.x=B.bv[k]}else if(r===320){k=m.be()
if(k!=null){l=J.mN(B.e.gB(k.bg()))
e.id=l
e.k1=0
l=l.length/3|0
e.k2=l
e.k3=l*2}}}l=e.id
i=l!=null
if(i&&e.d===B.aH)e.r=1
if(e.b===0||e.c===0)return
if(i&&e.f===8){h=l.length
for(i=l.$flags|0,s=0;s<h;++s){g=l[s]
i&2&&A.b(l)
l[s]=g>>>8}}if(e.d===B.aF)e.z=!0
e.w=e.r
if(t.ae(324)){e.ay=e.c8(322)
e.ch=e.c8(323)
e.CW=e.cW(324)
e.cx=e.cW(325)}else{e.ay=e.cV(322,e.b)
if(!t.ae(278))e.ch=e.cV(323,e.c)
else{f=e.c8(278)
if(f===-1)e.ch=e.c
else e.ch=f}e.CW=e.cW(273)
e.cx=e.cW(279)}l=e.b
i=e.ay
e.cy=B.a.au(l+i-1,i)
i=e.c
l=e.ch
e.db=B.a.au(i+l-1,l)
e.dy=e.cV(266,1)
e.fr=e.c8(292)
e.fx=e.c8(293)
e.c8(338)
switch(e.d.a){case 0:case 1:t=e.f
if(t===1&&e.r===1)e.y=B.aE
else if(t===4&&e.r===1)e.y=B.kh
else if(B.a.a1(t,8)===0){t=e.r
if(t===1)e.y=B.ki
else if(t===2)e.y=B.kj
else e.y=B.a0}break
case 2:if(B.a.a1(e.f,8)===0){t=e.r
if(t===3)e.y=B.ca
else if(t===4)e.y=B.kl
else e.y=B.a0}break
case 3:t=!1
if(e.r===1)if(e.id!=null){t=e.f
t=t===4||t===8||t===16}if(t)e.y=B.kk
break
case 4:if(e.f===1&&e.r===1)e.y=B.aE
break
case 6:if(e.e===7&&e.f===8&&e.r===3)e.y=B.ca
else{if(t.ae(530)){k=t.k(0,530).be()
e.as=k.h(0)
t=e.at=k.a4(0,1)}else t=e.at=e.as=2
l=e.as
l===$&&A.d()
if(l*t===1)e.y=B.a0
else if(e.f===8&&e.r===3)e.y=B.km}break
case 5:if(B.a.a1(e.f,8)===0)e.y=B.a0
t=e.r
if(t===4)e.w=3
else if(t===5)e.w=4
break
default:if(B.a.a1(e.f,8)===0)e.y=B.a0
break}},
bO(a2){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=null,a=c.x,a0=a===B.a_,a1=a===B.h
a=c.f
if(a===1)t=B.w
else if(a===2)t=B.y
else{if(a===4)a=B.z
else if(a0&&a===16)a=B.C
else if(a0&&a===32)a=B.H
else if(a0&&a===64)a=B.L
else if(a1&&a===8)a=B.M
else if(a1&&a===16)a=B.N
else if(a1&&a===32)a=B.O
else if(a===16)a=B.l
else a=a===32?B.I:B.f
t=a}s=c.id!=null&&c.d===B.aH
r=s?3:c.w
a=c.b
q=A.R(b,b,t,0,B.j,c.c,b,0,r,b,t,a,s)
if(s){a=q.a
a=a==null?b:a.gR()
a.toString
p=c.id
o=p.length
n=o/3|0
m=c.k1
m===$&&A.d()
l=c.k2
l===$&&A.d()
k=c.k3
k===$&&A.d()
for(j=k,i=l,h=m,g=0;g<n;++g,++h,++i,++j){if(j>=o)break
if(!(h<o))return A.a(p,h)
m=p[h]
if(!(i<o))return A.a(p,i)
a.b5(g,m,p[i],p[j])}}f=0
e=0
for(;;){a=c.db
a===$&&A.d()
if(!(f<a))break
d=0
for(;;){a=c.cy
a===$&&A.d()
if(!(d<a))break
c.hx(a2,q,d,f);++d;++e}++f}return q},
hx(b1,b2,b3,b4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9=this,b0=null
if(a9.y===B.aE){a9.hk(b1,b2,b3,b4)
return}q=a9.cy
q===$&&A.d()
p=b4*q+b3
q=a9.CW
if(!(p>=0&&p<q.length))return A.a(q,p)
b1.d=q[p]
q=a9.ay
o=b3*q
n=a9.ch
m=b4*n
l=a9.cx
if(!(p<l.length))return A.a(l,p)
t=l[p]
k=q*n*a9.r
q=a9.f
n=q===16
if(n)k*=2
else if(q===32)k*=4
s=null
if(q===8||n||q===32||q===64){q=a9.e
if(q===1)s=b1
else if(q===5){s=A.v(new Uint8Array(k),!1,b0,0)
r=A.lu()
try{r.eZ(A.o(b1,t,0),s.a)}catch(j){}if(a9.Q===2)for(i=0;i<a9.ch;++i){h=a9.r
q=a9.ay
g=h*(i*q+1)
f=q*h
for(;h<f;++h){q=s
n=J.c(q.a,q.d+g)
l=s
e=a9.r
e=J.c(l.a,l.d+(g-e))
J.x(q.a,q.d+g,n+e);++g}}}else if(q===32773){s=A.v(new Uint8Array(k),!1,b0,0)
a9.e9(b1,k,s.a)}else if(q===32946)s=A.v(B.B.bP(b1.cw(0,0,t)),!1,b0,0)
else if(q===8)s=A.v(B.B.bP(b1.cw(0,0,t)),!1,b0,0)
else if(q===6||q===7){a9.hZ(new A.fy().bO(u.D.a(b1.cw(0,0,t))),b2,o,m,a9.ay,a9.ch)
return}else throw A.f(A.n("Unsupported Compression Type: "+q))
d=A.j([0,0,0],u.t)
for(c=m,b=0;b<a9.ch;++b,++c)for(a=o,a0=0;a0<a9.ay;++a0,++a){q=s
if(q.d>=q.c||a>=a9.b||c>=a9.c)break
q=a9.r
if(q===1){q=a9.x
if(q===B.a_){q=a9.f
if(q===32){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.bN()
if(0>=q.length)return A.a(q,0)
a1=q[0]}else if(q===64)a1=s.d6()
else if(q===16){q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a1=n[q]}else a1=0
if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.aC(a,c,a1)}}else{n=a9.f
if(n===8)if(q===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a1=q[0]}else{q=s
a1=J.c(q.a,q.d++)}else if(n===16)if(q===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a1=q[0]}else a1=s.m()
else if(n===32)if(q===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a1=q[0]}else a1=s.l()
else a1=0
if(a9.d===B.aF){q=b2.a
a2=q==null?b0:q.gE()
a1=(a2==null?0:a2)-a1}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.aC(a,c,a1)}}}else if(q===2){q=a9.f
if(q===8){if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a3=q[0]}else{q=s
a3=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else{q=s
a4=J.c(q.a,q.d++)}}else if(q===16){if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a3=q[0]}else a3=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else a4=s.m()}else if(q===32){if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a3=q[0]}else a3=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else a4=s.l()}else{a3=0
a4=0}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.a3(a,c,a3,a4,0)}}else if(q===3){q=a9.x
if(q===B.a_){q=a9.f
if(q===32){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.bN()
if(0>=q.length)return A.a(q,0)
a5=q[0]
n[0]=s.l()
a6=q[0]
n[0]=s.l()
a7=q[0]}else{a6=0
a7=0
if(q===64)a5=s.d6()
else if(q===16){q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a5=n[q]
q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a6=n[q]
q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a7=n[q]}else a5=0}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.a3(a,c,a5,a6,a7)}}else{n=a9.f
if(n===8){if(q===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else{q=s
a5=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else{q=s
a6=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else{q=s
a7=J.c(q.a,q.d++)}}else if(n===16){if(q===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else a5=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else a6=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else a7=s.m()}else if(n===32){if(q===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else a5=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else a6=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else a7=s.l()}else{a5=0
a6=0
a7=0}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.a3(a,c,a5,a6,a7)}}}else if(q>=4)if(a9.x===B.a_){q=a9.f
if(q===32){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.bN()
if(0>=q.length)return A.a(q,0)
a5=q[0]
n[0]=s.l()
a6=q[0]
n[0]=s.l()
a7=q[0]
n[0]=s.l()
a8=q[0]}else{a6=0
a7=0
a8=0
if(q===64)a5=s.d6()
else if(q===16){q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a5=n[q]
q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a6=n[q]
q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a7=n[q]
q=s.m()
n=$.N
n=n!=null?n:A.U()
if(!(q<n.length))return A.a(n,q)
a8=n[q]}else a5=0}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.ak(a,c,a5,a6,a7,a8)}}else{q=b2.a
a4=q==null?b0:q.gE()
if(a4==null)a4=0
q=a9.f
if(q===8){if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else{q=s
a5=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else{q=s
a6=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else{q=s
a7=J.c(q.a,q.d++)}if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a8=q[0]}else{q=s
a8=J.c(q.a,q.d++)}if(a9.r===5)if(a9.x===B.h){q=s
q=J.c(q.a,q.d++)
n=$.an()
n.$flags&2&&A.b(n)
n[0]=q
q=$.av()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else{q=s
a4=J.c(q.a,q.d++)}}else if(q===16){if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else a5=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else a6=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else a7=s.m()
if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a8=q[0]}else a8=s.m()
if(a9.r===5)if(a9.x===B.h){q=s.m()
n=$.am()
n.$flags&2&&A.b(n)
n[0]=q
q=$.au()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else a4=s.m()}else if(q===32){if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a5=q[0]}else a5=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a6=q[0]}else a6=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a7=q[0]}else a7=s.l()
if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a8=q[0]}else a8=s.l()
if(a9.r===5)if(a9.x===B.h){q=s.l()
n=$.K()
n.$flags&2&&A.b(n)
n[0]=q
q=$.a4()
if(0>=q.length)return A.a(q,0)
a4=q[0]}else a4=s.l()}else{a5=0
a6=0
a7=0
a8=0}if(a9.d===B.cb){A.mf(a5,a6,a7,a8,d)
a5=d[0]
a6=d[1]
a7=d[2]
a8=a4}if(a<a9.b&&c<a9.c){q=b2.a
if(q!=null)q.ak(a,c,a5,a6,a7,a8)}}}}else throw A.f(A.n("Unsupported bitsPerSample: "+q))},
hZ(a,b,c,d,e,f){var t,s,r,q
for(t=0;t<f;++t)for(s=t+d,r=0;r<e;++r){q=a.a
q=q==null?null:q.L(r,t,null)
if(q==null)q=new A.G()
b.bI(r+c,s,q)}},
hk(a4,a5,a6,a7){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=this,a2=null,a3=a1.cy
a3===$&&A.d()
s=a7*a3+a6
a3=a1.CW
if(!(s>=0&&s<a3.length))return A.a(a3,s)
a4.d=a3[s]
a3=a1.ay
r=a6*a3
q=a1.ch
p=a7*q
o=a1.cx
if(!(s<o.length))return A.a(o,s)
n=o[s]
t=null
o=a1.e
if(o===32773){m=B.a.a1(a3,8)===0?B.a.Y(a3,8)*q:(B.a.Y(a3,8)+1)*q
t=A.v(new Uint8Array(a3*q),!1,a2,0)
a1.e9(a4,m,t.a)}else if(o===5){t=A.v(new Uint8Array(a3*q),!1,a2,0)
A.lu().eZ(A.o(a4,n,0),t.a)
if(a1.Q===2)for(l=0;l<a1.c;++l){k=a1.r
j=k*(l*a1.b+1)
for(;k<a1.b*a1.r;++k){a3=t
q=J.c(a3.a,a3.d+j)
o=t
i=a1.r
i=J.c(o.a,o.d+(j-i))
J.x(a3.a,a3.d+j,q+i);++j}}}else if(o===2){t=A.v(new Uint8Array(a3*q),!1,a2,0)
try{A.km(a1.dy,a3,q).j0(t,a4,0,a1.ch)}catch(h){}}else if(o===3){t=A.v(new Uint8Array(a3*q),!1,a2,0)
try{A.km(a1.dy,a3,q).j1(t,a4,0,a1.ch,a1.fr)}catch(h){}}else if(o===4){t=A.v(new Uint8Array(a3*q),!1,a2,0)
try{A.km(a1.dy,a3,q).j5(t,a4,0,a1.ch,a1.fx)}catch(h){}}else if(o===8)t=A.v(B.B.bP(a4.cw(0,0,n)),!1,a2,0)
else if(o===32946)t=A.v(B.B.bP(a4.cw(0,0,n)),!1,a2,0)
else if(o===1)t=a4
else throw A.f(A.n("Unsupported Compression Type: "+o))
g=new A.ii(t)
f=a5.gE()
a3=a1.z
e=a3?f:0
d=a3?0:f
for(c=p,b=0;b<a1.ch;++b,++c){for(a=r,a0=0;a0<a1.ay;++a0,++a){a3=a5.a
q=a3==null
o=q?a2:a3.b
if(c<(o==null?0:o)){a3=q?a2:a3.a
a3=a>=(a3==null?0:a3)}else a3=!0
if(a3)break
a3=g.af(1)
q=a5.a
if(a3===0){if(q!=null)q.a3(a,c,e,0,0)}else if(q!=null)q.a3(a,c,d,0,0)}g.c=0}},
e9(a,b,c){var t,s,r,q,p,o,n,m,l,k
u.L.a(c)
for(t=J.aI(c),s=0,r=0;r<b;){q=s+1
p=J.c(a.a,a.d+s)
o=$.an()
o.$flags&2&&A.b(o)
o[0]=p
p=$.av()
if(0>=p.length)return A.a(p,0)
n=p[0]
if(n>=0&&n<=127)for(p=n+1,s=q,m=0;m<p;++m,r=l,s=q){l=r+1
q=s+1
t.i(c,r,J.c(a.a,a.d+s))}else{p=n<=-1&&n>=-127
s=q+1
if(p){k=J.c(a.a,a.d+q)
for(p=-n+1,m=0;m<p;++m,r=l){l=r+1
t.i(c,r,k)}}}}},
cV(a,b){var t=this.a
if(!t.ae(a))return b
t=t.k(0,a).be()
t=t==null?null:t.h(0)
return t==null?0:t},
c8(a){return this.cV(a,0)},
cW(a){var t,s=this.a
if(!s.ae(a))return null
t=s.k(0,a)
s=t.be()
s.toString
return A.lt(t.c,s.gby(s),u.p)}}
A.cn.prototype={
ad(){return"TiffFormat."+this.b}}
A.a5.prototype={
ad(){return"TiffPhotometricType."+this.b}}
A.aP.prototype={
ad(){return"TiffImageType."+this.b}}
A.h2.prototype={$iJ:1}
A.i1.prototype={
eZ(a,b){var t,s,r,q,p,o,n,m,l=this
u.L.a(b)
l.r=b
t=J.ao(b)
l.w=0
s=u.D.a(a.a)
l.e=s
r=l.f=s.length
l.b=a.d
if(0>=r)return A.a(s,0)
if(s[0]===0){if(1>=r)return A.a(s,1)
s=s[1]===1}else s=!1
if(s)throw A.f(A.n("Invalid LZW Data"))
l.eo()
l.d=l.c=0
q=l.dq()
s=l.x
p=0
for(;;){if(!(q!==257&&l.w<t))break
if(q===256){l.eo()
q=l.dq()
l.as=0
if(q===257)break
J.x(l.r,l.w++,q)
p=q}else{r=l.Q
r.toString
if(q<r){l.el(q)
r=l.as
r===$&&A.d()
o=r-1
for(;o>=0;--o){r=l.r
n=l.w++
if(!(o<4096))return A.a(s,o)
J.x(r,n,s[o])}r=l.as-1
if(!(r>=0&&r<4096))return A.a(s,r)
l.dY(p,s[r])}else{l.el(p)
r=l.as
r===$&&A.d()
o=r-1
for(;o>=0;--o){r=l.r
n=l.w++
if(!(o<4096))return A.a(s,o)
J.x(r,n,s[o])}r=l.r
n=l.w++
m=l.as-1
if(!(m>=0&&m<4096))return A.a(s,m)
J.x(r,n,s[m])
m=l.as-1
if(!(m>=0&&m<4096))return A.a(s,m)
l.dY(p,s[m])}p=q}q=l.dq()}},
dY(a,b){var t,s=this,r=s.y
r===$&&A.d()
t=s.Q
t.toString
r.$flags&2&&A.b(r)
if(!(t<4096))return A.a(r,t)
r[t]=b
r=s.z
r===$&&A.d()
r.$flags&2&&A.b(r)
r[t]=a
t=s.Q=t+1
if(t===511)s.a=10
else if(t===1023)s.a=11
else if(t===2047)s.a=12},
el(a){var t,s,r,q,p,o,n,m=this
m.as=0
t=m.x
m.as=1
s=m.y
s===$&&A.d()
if(!(a<4096))return A.a(s,a)
r=s[a]
t.$flags&2&&A.b(t)
t[0]=r
r=m.z
r===$&&A.d()
q=r[a]
for(p=1;q!==4098;p=o){o=p+1
m.as=o
if(!(q>=0&&q<4096))return A.a(s,q)
n=s[q]
if(!(p<4096))return A.a(t,p)
t[p]=n
q=r[q]}},
dq(){var t,s,r,q,p=this,o=p.b,n=p.f
n===$&&A.d()
if(o>=n)return 257
for(;t=p.d,s=p.a,t<s;o=q){if(o>=n)return 257
s=p.c
r=p.e
r===$&&A.d()
q=o+1
p.b=q
if(!(o>=0&&o<r.length))return A.a(r,o)
p.c=(s<<8>>>0)+r[o]>>>0
p.d=t+8}o=t-s
p.d=o
o=B.a.a0(p.c,o)
s-=9
if(!(s>=0&&s<4))return A.a(B.bc,s)
return o&B.bc[s]},
eo(){var t,s,r=this
r.y=new Uint8Array(4096)
t=new Uint32Array(4096)
r.z=t
B.o.aB(t,0,4096,4098)
for(t=r.y,s=0;s<256;++s){t.$flags&2&&A.b(t)
t[s]=s}r.a=9
r.Q=258}}
A.ij.prototype={
al(a){var t,s,r=this.a
if(r==null)return null
r=r.f
if(!(a<r.length))return A.a(r,a)
r=r[a]
t=this.c
t===$&&A.d()
s=r.bO(t)
return s},
aS(a,b){var t,s,r,q=this,p=null,o=A.v(a,!1,p,0)
q.c=o
o=q.a=q.ey(o)
if(o==null)return p
t=o.f.length
s=q.al(0)
if(s==null)return p
s.e=A.jP(A.v(a,!1,p,0))
s.w=B.aU
for(r=1;r<t;++r)s.aZ(q.al(r))
return s},
ey(a){var t,s,r,q,p,o,n,m,l,k,j=null,i=A.j([],u.aU),h=new A.h2(i),g=a.m()
if(g!==18761&&g!==19789)return j
if(g===19789)a.e=!0
else a.e=!1
r=a.m()
h.d=r
if(r!==42)return j
q=a.l()
p=A.o(a,j,0)
p.d=q
t=p
for(r=u.p,o=u.cV;q!==0;){s=null
try{n=new A.h1(A.D(r,o),B.aG,B.c9,B.kn)
n.fW(t)
s=n
m=s
if(!(m.b!==0&&m.c!==0))break}catch(l){break}B.c.A(i,s)
m=i.length
if(m===1){if(0>=m)return A.a(i,0)
k=i[0]
h.a=k.b
if(0>=m)return A.a(i,0)
h.b=k.c}q=t.l()
if(q!==0)t.d=q}return i.length!==0?h:j}}
A.iq.prototype={
cn(){var t,s=this.a,r=s.bf()
if((r&1)!==0)return!1
if((r>>>1&7)>3)return!1
if((r>>>4&1)===0)return!1
this.f.d=r>>>5
if(s.bf()!==2752925)return!1
t=this.b
t.a=s.m()
t.b=s.m()
return!0},
bF(){var t,s,r,q,p=this,o=null
if(!p.hP())return o
t=p.b
s=t.a
p.d=A.R(o,o,B.f,0,B.j,t.b,o,0,4,o,B.f,s,!1)
p.hU()
if(!p.i5())return o
s=t.w
if(s.length!==0){r=A.v(new A.aJ(s),!1,o,0)
s=p.d
s.toString
s.e=A.jP(r)}q=t.r
if(q!=null)p.d.c=new A.bf("",B.P,q)
return p.d},
hP(){var t,s,r,q,p=this
if(!p.cn())return!1
p.fr=A.os()
for(t=p.dy,s=0;s<4;++s){r=new Int32Array(2)
q=new Int32Array(2)
B.c.i(t,s,new A.h9(r,q,new Int32Array(2)))}p.y=p.Q=0
t=p.b
r=t.a
p.z=r
t=t.b
p.as=t
p.at=r+15>>>4
p.ax=t+15>>>4
p.k1=0
t=p.a
r=p.f
q=r.d
q===$&&A.d()
q=A.lK(t.ai(q))
p.c=q
t.d+=r.d
q.X(1)
p.c.X(1)
p.ib(p.x,p.fr)
p.i4()
if(!p.i7(t))return!1
p.i9()
p.c.X(1)
p.i8()
return!0},
ib(a,b){var t,s,r,q=this,p=q.c
p===$&&A.d()
p=p.X(1)!==0
a.a=p
if(p){a.b=q.c.X(1)!==0
if(q.c.X(1)!==0){a.c=q.c.X(1)!==0
for(p=a.d,t=0;t<4;++t){if(q.c.X(1)!==0){s=q.c
r=s.X(7)
s=s.X(1)===1?-r:r}else s=0
p.$flags&2&&A.b(p)
p[t]=s}for(p=a.e,t=0;t<4;++t){if(q.c.X(1)!==0){s=q.c
r=s.X(6)
s=s.X(1)===1?-r:r}else s=0
p.$flags&2&&A.b(p)
p[t]=s}}if(a.b)for(t=0;t<3;++t){p=b.a
s=q.c.X(1)!==0?q.c.X(8):255
p.$flags&2&&A.b(p)
p[t]=s}}else a.b=!1
return!0},
i4(){var t,s,r,q=this,p=q.w,o=q.c
o===$&&A.d()
p.a=o.X(1)!==0
p.b=q.c.X(6)
p.c=q.c.X(3)
o=q.c.X(1)!==0
p.d=o
if(o)if(q.c.X(1)!==0){for(o=p.e,t=0;t<4;++t)if(q.c.X(1)!==0){s=q.c
r=s.X(6)
s=s.X(1)===1?-r:r
o.$flags&2&&A.b(o)
o[t]=s}for(o=p.f,t=0;t<4;++t)if(q.c.X(1)!==0){s=q.c
r=s.X(6)
s=s.X(1)===1?-r:r
o.$flags&2&&A.b(o)
o[t]=s}}if(p.b===0)o=0
else o=p.a?1:2
q.c1=o
return!0},
i7(a){var t,s,r,q,p,o,n,m=a.c-a.d,l=this.c
l===$&&A.d()
l=B.a.O(1,l.X(2))
this.cy=l
t=l-1
s=t*3
if(m<s)return!1
for(l=this.db,r=0,q=0;q<t;++q,s=o){p=a.cH(3,r)
o=s+((J.c(p.a,p.d)|J.c(p.a,p.d+1)<<8|J.c(p.a,p.d+2)<<16)>>>0)
if(o>m)o=m
n=new A.eu(a.bU(o-s,s))
n.b=254
n.c=0
n.d=-8
B.c.i(l,q,n)
r+=3}B.c.i(l,t,A.lK(a.bU(m-s,a.d-a.b+s)))
return s<m},
i9(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=this,f=g.c
f===$&&A.d()
t=f.X(7)
s=g.c.X(1)!==0?g.c.cb(4):0
r=g.c.X(1)!==0?g.c.cb(4):0
q=g.c.X(1)!==0?g.c.cb(4):0
p=g.c.X(1)!==0?g.c.cb(4):0
o=g.c.X(1)!==0?g.c.cb(4):0
n=g.x
for(f=g.dy,m=n.d,l=0;l<4;++l){if(n.a){k=m[l]
if(!n.c)k+=t}else{if(l>0){j=f[0]
if(!(l>=0&&l<4))return A.a(f,l)
f[l]=j
continue}k=t}i=f[l]
j=i.a
h=k+s
if(h<0)h=0
else if(h>127)h=127
h=B.av[h]
j.$flags&2&&A.b(j)
j[0]=h
if(k<0)h=0
else h=k>127?127:k
j[1]=B.aw[h]
h=i.b
j=k+r
if(j<0)j=0
else if(j>127)j=127
j=B.av[j]
h.$flags&2&&A.b(h)
h[0]=j*2
j=k+q
if(j<0)j=0
else if(j>127)j=127
h[1]=B.aw[j]*101581>>>16
if(h[1]<8)h[1]=8
j=i.c
h=k+p
if(h<0)h=0
else if(h>117)h=117
h=B.av[h]
j.$flags&2&&A.b(j)
j[0]=h
h=k+o
if(h<0)h=0
else if(h>127)h=127
j[1]=B.aw[h]}},
i8(){var t,s,r,q,p,o,n=this,m=n.fr
for(t=0;t<4;++t)for(s=0;s<8;++s)for(r=0;r<3;++r)for(q=0;q<11;++q){p=n.c
p===$&&A.d()
o=p.a7(B.j0[t][s][r][q])!==0?n.c.X(8):B.e5[t][s][r][q]
p=m.b
if(!(t<p.length))return A.a(p,t)
p=p[t]
if(!(s<p.length))return A.a(p,s)
p=p[s].a
if(!(r<p.length))return A.a(p,r)
p=p[r]
p.$flags&2&&A.b(p)
p[q]=o}p=n.c
p===$&&A.d()
p=p.X(1)!==0
n.fx=p
if(p)n.fy=n.c.X(8)},
ie(){var t,s,r,q,p,o,n,m,l,k,j,i,h=this,g=h.c1
g.toString
if(g>0){t=h.w
for(g=t.e,s=t.f,r=h.x,q=r.e,p=0;p<4;++p){if(r.a){o=q[p]
if(!r.c){n=t.b
n.toString
o+=n}}else o=t.b
for(m=0;m<=1;++m){n=h.dF
n===$&&A.d()
if(!(p<n.length))return A.a(n,p)
l=n[p][m]
n=t.d
n===$&&A.d()
if(n){o.toString
k=o+g[0]
if(m!==0)k+=s[0]}else k=o
k.toString
if(k<0)k=0
else if(k>63)k=63
if(k>0){n=t.c
n===$&&A.d()
if(n>0){j=n>4?B.a.j(k,2):B.a.j(k,1)
i=9-n
if(j>i)j=i}else j=k
if(j<1)j=1
l.b=j
l.a=2*k+j
if(k>=40)n=2
else n=k>=15?1:0
l.d=n}else l.a=0
l.c=m!==0}}}},
hU(){var t,s,r,q,p,o,n,m,l,k,j,i=this,h=null,g=i.b,f=g.at
if(f!=null)i.dG=f
t=J.ag(4,u.e6)
for(f=u.ao,s=0;s<4;++s)t[s]=A.j([new A.bq(),new A.bq()],f)
i.dF=u.gS.a(t)
f=i.at
f.toString
t=J.ag(f,u.dE)
for(r=0;r<f;++r){q=new Uint8Array(16)
p=new Uint8Array(8)
t[r]=new A.ey(q,p,new Uint8Array(8))}i.k2=u.cC.a(t)
i.ok=new Uint8Array(832)
f=i.at
f.toString
i.go=new Uint8Array(4*f)
q=i.p4=16*f
p=i.R8=8*f
o=i.c1
o.toString
if(!(o<3))return A.a(B.a4,o)
n=B.a4[o]
m=n*q
l=(n/2|0)*p
i.p1=A.v(new Uint8Array(16*q+m),!1,h,m)
q=8*p+l
i.p2=A.v(new Uint8Array(q),!1,h,l)
i.p3=A.v(new Uint8Array(q),!1,h,l)
g=g.a
i.RG=A.v(new Uint8Array(g),!1,h,0)
k=g+1>>>1
i.rx=A.v(new Uint8Array(k),!1,h,0)
i.ry=A.v(new Uint8Array(k),!1,h,0)
if(o===2)i.ch=i.ay=0
else{g=B.a.Y(i.y-n,16)
i.ay=g
q=B.a.Y(i.Q-n,16)
i.ch=q
if(g<0)i.ay=0
if(q<0)i.ch=0}g=B.a.Y(i.as+15+n,16)
i.cx=g
q=B.a.Y(i.z+15+n,16)
i.CW=q
if(q>f)i.CW=f
q=i.ax
q.toString
if(g>q)i.cx=q
j=f+1
t=J.ag(j,u.ai)
for(r=0;r<j;++r)t[r]=new A.ew()
i.k3=u.eQ.a(t)
g=i.at
g.toString
t=J.ag(g,u.gU)
for(r=0;r<g;++r){f=new Int16Array(384)
t[r]=new A.ex(f,new Uint8Array(16))}i.co=u.db.a(t)
g=i.at
g.toString
i.k4=u.ge.a(A.P(g,h,!1,u.aj))
i.ie()
A.nT()
i.e=new A.ir()
return!0},
i5(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=this
f.y2=0
t=f.id
s=f.x
r=f.db
q=0
for(;;){p=f.cx
p.toString
if(!(q<p))break
p=f.cy
p===$&&A.d()
p=(q&p-1)>>>0
if(!(p>=0&&p<8))return A.a(r,p)
o=r[p]
for(;;){q=f.y1
p=f.at
p.toString
if(!(q<p))break
p=f.k3
p===$&&A.d()
n=p.length
if(0>=n)return A.a(p,0)
m=p[0]
l=1+q
if(!(l<n))return A.a(p,l)
k=p[l]
l=f.co
l===$&&A.d()
if(!(q<l.length))return A.a(l,q)
j=l[q]
if(s.b){q=f.c
q===$&&A.d()
q=q.a7(f.fr.a[0])
p=f.c
n=f.fr
f.k1=q===0?p.a7(n.a[1]):2+p.a7(n.a[2])}q=f.fx
q===$&&A.d()
if(q){q=f.c
q===$&&A.d()
p=f.fy
p===$&&A.d()
i=q.a7(p)!==0}else i=!1
f.i6()
if(!i)i=f.ia(k,o)
else{m.a=k.a=0
q=j.b
q===$&&A.d()
if(!q)m.b=k.b=0
j.f=j.e=0}q=f.c1
q.toString
if(q>0){q=f.k4
q===$&&A.d()
p=f.y1
n=f.dF
n===$&&A.d()
l=f.k1
l===$&&A.d()
if(!(l<n.length))return A.a(n,l)
l=n[l]
n=j.b
n===$&&A.d()
B.c.i(q,p,l[n?1:0])
q=f.k4
p=f.y1
if(!(p<q.length))return A.a(q,p)
h=q[p]
h.c=h.c||!i}++f.y1}q=f.k3
q===$&&A.d()
if(0>=q.length)return A.a(q,0)
q=q[0]
q.b=q.a=0
B.e.aB(t,0,4,0)
f.y1=0
f.iJ()
q=f.c1
q.toString
g=!1
if(q>0){q=f.y2
p=f.ch
p===$&&A.d()
if(q>=p){p=f.cx
p.toString
p=q<=p
g=p}}if(!f.hN(g))return!1
q=++f.y2}return!0},
iJ(){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3=this,a4=null,a5=a3.y2,a6=a3.ok
a6===$&&A.d()
t=A.v(a6,!1,a4,40)
s=A.v(a6,!1,a4,584)
r=A.v(a6,!1,a4,600)
a6=a5>0
q=0
for(;;){p=a3.at
p.toString
if(!(q<p))break
p=a3.co
p===$&&A.d()
if(!(q<p.length))return A.a(p,q)
o=p[q]
if(q>0){for(n=-1;n<16;++n){p=n*32
t.bd(p-4,4,t,p+12)}for(n=-1;n<8;++n){p=n*32
m=p-4
p+=4
s.bd(m,4,s,p)
r.bd(m,4,r,p)}}else{for(n=0;n<16;++n)J.x(t.a,t.d+(n*32-1),129)
for(n=0;n<8;++n){p=n*32-1
J.x(s.a,s.d+p,129)
J.x(r.a,r.d+p,129)}if(a6){J.x(r.a,r.d+-33,129)
J.x(s.a,s.d+-33,129)
J.x(t.a,t.d+-33,129)}}p=a3.k2
p===$&&A.d()
if(!(q<p.length))return A.a(p,q)
l=p[q]
k=o.a
j=o.e
if(a6){t.bR(-32,16,l.a)
s.bR(-32,8,l.b)
r.bR(-32,8,l.c)}else if(q===0){p=t.a
m=t.d+-33
J.b9(p,m,m+21,127)
m=s.a
p=s.d+-33
J.b9(m,p,p+9,127)
p=r.a
m=r.d+-33
J.b9(p,m,m+9,127)}p=o.b
p===$&&A.d()
if(p){i=A.o(t,a4,-16)
h=i.cz()
if(a6){p=a3.at
p.toString
if(q>=p-1){p=l.a[15]
m=i.a
g=i.d
J.b9(m,g,g+4,p)}else{p=a3.k2
m=q+1
if(!(m<p.length))return A.a(p,m)
i.bR(0,4,p[m].a)}}p=h.length
if(0>=p)return A.a(h,0)
f=h[0]
h.$flags&2&&A.b(h)
if(96>=p)return A.a(h,96)
h[96]=f
h[64]=f
h[32]=f
for(p=o.c,e=0;e<16;++e,j=j<<2>>>0){d=A.o(t,a4,B.bO[e])
m=p[e]
if(!(m<10))return A.a(B.bC,m)
B.bC[m].$1(d)
j.toString
m=e*16
a3.ec(j,new A.aa(k,m,Math.min(384,384),m,!1),d)}}else{p=A.lM(q,a5,o.c[0])
p.toString
if(!(p<7))return A.a(B.bN,p)
B.bN[p].$1(t)
if(j!==0)for(e=0;e<16;++e,j=j<<2>>>0){d=A.o(t,a4,B.bO[e])
j.toString
p=e*16
a3.ec(j,new A.aa(k,p,Math.min(384,384),p,!1),d)}}p=o.f
p===$&&A.d()
m=A.lM(q,a5,o.d)
m.toString
if(!(m<7))return A.a(B.ax,m)
B.ax[m].$1(s)
B.ax[m].$1(r)
m=Math.min(384,384)
c=new A.aa(k,256,m,256,!1)
if((p&255)!==0){g=a3.e
if((p&170)!==0){g===$&&A.d()
g.bz(c,s)
g.bz(A.o(c,a4,16),A.o(s,a4,4))
b=A.o(c,a4,32)
a=A.o(s,a4,128)
g.bz(b,a)
g.bz(A.o(b,a4,16),A.o(a,a4,4))}else{g===$&&A.d()
g.fh(c,s)}}a0=new A.aa(k,320,m,320,!1)
p=p>>>8
if((p&255)!==0){m=a3.e
if((p&170)!==0){m===$&&A.d()
m.bz(a0,r)
m.bz(A.o(a0,a4,16),A.o(r,a4,4))
p=A.o(a0,a4,32)
g=A.o(r,a4,128)
m.bz(p,g)
m.bz(A.o(p,a4,16),A.o(g,a4,4))}else{m===$&&A.d()
m.fh(a0,r)}}p=a3.ax
p.toString
if(a5<p-1){B.e.ar(l.a,0,16,t.a2(),480)
B.e.ar(l.b,0,8,s.a2(),224)
B.e.ar(l.c,0,8,r.a2(),224)}a1=q*16
a2=q*8
for(n=0;n<16;++n){p=a3.p4
p.toString
m=a3.p1
m===$&&A.d()
m.bd(a1+n*p,16,t,n*32)}for(n=0;n<8;++n){p=a3.R8
p.toString
m=a3.p2
m===$&&A.d()
g=n*32
m.bd(a2+n*p,8,s,g)
p=a3.R8
p.toString
m=a3.p3
m===$&&A.d()
m.bd(a2+n*p,8,r,g)}++q}},
ec(a,b,c){var t,s,r,q,p,o
switch(a>>>30){case 3:t=this.e
t===$&&A.d()
t.jz(b,c,!1)
break
case 2:this.e===$&&A.d()
s=J.c(b.a,b.d)+4
r=B.a.aq(B.a.j(J.c(b.a,b.d+4)*35468,16),32)
q=B.a.aq(B.a.j(J.c(b.a,b.d+4)*85627,16),32)
p=B.a.aq(B.a.j(J.c(b.a,b.d+1)*35468,16),32)
o=B.a.aq(B.a.j(J.c(b.a,b.d+1)*85627,16),32)
A.it(c,0,s+q,o,p)
A.it(c,1,s+r,o,p)
A.it(c,2,s-r,o,p)
A.it(c,3,s-q,o,p)
break
case 1:t=this.e
t===$&&A.d()
t.cA(b,c)
break
default:break}},
hC(a,b){var t,s,r,q,p,o,n,m,l,k,j,i=this,h=null,g=i.p4,f=i.k4
f===$&&A.d()
if(!(a>=0&&a<f.length))return A.a(f,a)
f=f[a]
f.toString
t=i.p1
t===$&&A.d()
s=A.o(t,h,a*16)
r=f.b
q=f.a
if(q===0)return
if(i.c1===1){if(a>0){t=i.e
t===$&&A.d()
g.toString
t.dP(s,g,q+4)}if(f.c){t=i.e
t===$&&A.d()
g.toString
t.fv(s,g,q)}if(b>0){t=i.e
t===$&&A.d()
g.toString
t.dQ(s,g,q+4)}if(f.c){f=i.e
f===$&&A.d()
g.toString
f.fw(s,g,q)}}else{p=i.R8
t=i.p2
t===$&&A.d()
o=a*8
n=A.o(t,h,o)
t=i.p3
t===$&&A.d()
m=A.o(t,h,o)
l=f.d
if(a>0){t=i.e
t===$&&A.d()
g.toString
o=q+4
t.c7(s,1,g,16,o,r,l)
p.toString
t.c7(n,1,p,8,o,r,l)
t.c7(m,1,p,8,o,r,l)}if(f.c){t=i.e
t===$&&A.d()
g.toString
t.jd(s,g,q,r,l)
p.toString
k=A.o(n,h,4)
j=A.o(m,h,4)
t.c6(k,1,p,8,q,r,l)
t.c6(j,1,p,8,q,r,l)}if(b>0){t=i.e
t===$&&A.d()
g.toString
o=q+4
t.c7(s,g,1,16,o,r,l)
p.toString
t.c7(n,p,1,8,o,r,l)
t.c7(m,p,1,8,o,r,l)}if(f.c){f=i.e
f===$&&A.d()
g.toString
f.jC(s,g,q,r,l)
p.toString
t=4*p
k=A.o(n,h,t)
j=A.o(m,h,t)
f.c6(k,p,1,8,q,r,l)
f.c6(j,p,1,8,q,r,l)}}},
hL(){var t,s=this,r=s.ay
r===$&&A.d()
t=r
for(;;){r=s.CW
r.toString
if(!(t<r))break
s.hC(t,s.y2);++t}},
hN(a1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=this,a=null,a0=b.c1
a0.toString
if(!(a0<3))return A.a(B.a4,a0)
t=B.a4[a0]
a0=b.p4
a0.toString
s=t*a0
a0=b.R8
a0.toString
r=(t/2|0)*a0
a0=b.p1
a0===$&&A.d()
q=-s
p=A.o(a0,a,q)
a0=b.p2
a0===$&&A.d()
o=-r
n=A.o(a0,a,o)
a0=b.p3
a0===$&&A.d()
m=A.o(a0,a,o)
l=b.y2
a0=b.cx
a0.toString
k=l*16
j=(l+1)*16
if(a1)b.hL()
if(l!==0){k-=t
b.to=A.o(p,a,0)
b.x1=A.o(n,a,0)
b.x2=A.o(m,a,0)}else{b.to=A.o(b.p1,a,0)
b.x1=A.o(b.p2,a,0)
b.x2=A.o(b.p3,a,0)}a0=l<a0-1
if(a0)j-=t
i=b.as
if(j>i)j=i
b.xr=null
if(b.dG!=null&&k<j){h=b.xr=b.hy(k,j-k)
if(h==null)return!1}else h=a
g=b.Q
if(k<g){f=g-k
e=b.to
e===$&&A.d()
d=e.d
c=b.p4
c.toString
e.d=d+c*f
c=b.x1
c===$&&A.d()
d=c.d
e=b.R8
e.toString
e*=B.a.j(f,1)
c.d=d+e
d=b.x2
d===$&&A.d()
d.d+=e
if(h!=null)h.d=h.d+b.b.a*f
k=g}if(k<j){e=b.to
e===$&&A.d()
d=e.d
c=b.y
e.d=d+c
d=b.x1
d===$&&A.d()
e=c>>>1
d.d=d.d+e
d=b.x2
d===$&&A.d()
d.d+=e
if(h!=null)h.d+=c
b.ik(k-g,b.z-c,j-k)}if(a0){a0=b.p1
h=b.p4
h.toString
a0.bd(q,s,p,16*h)
h=b.p2
q=b.R8
q.toString
h.bd(o,r,n,8*q)
q=b.p3
h=b.R8
h.toString
q.bd(o,r,m,8*h)}return!0},
ik(a,b,c){if(b<=0||c<=0)return!1
this.hE(a,b,c)
this.hD(a,b,c)
return!0},
df(a){var t
if((a&-4194304)>>>0===0)t=B.a.j(a,14)
else t=a<0?0:255
return t},
d_(a,b,c,d){var t=19077*a
d.i(0,0,this.df(t+26149*c+-3644112))
d.i(0,1,this.df(t-6419*b-13320*c+2229552))
d.i(0,2,this.df(t+33050*b+-4527440))},
cZ(a6,a7,a8,a9,b0,b1,b2,b3,b4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=this,a=null,a0=new A.iC(),a1=b4-1,a2=B.a.j(a1,1),a3=a0.$2(J.c(a8.a,a8.d),J.c(a9.a,a9.d)),a4=a0.$2(J.c(b0.a,b0.d),J.c(b1.a,b1.d)),a5=B.a.j(3*a3+a4+131074,2)
b.d_(J.c(a6.a,a6.d),a5&255,a5>>>16,b2)
b2.i(0,3,255)
t=a7!=null
if(t){a5=B.a.j(3*a4+a3+131074,2)
s=J.c(a7.a,a7.d)
b3.toString
b.d_(s,a5&255,a5>>>16,b3)
b3.i(0,3,255)}for(r=1;r<=a2;++r,a4=p,a3=q){q=a0.$2(J.c(a8.a,a8.d+r),J.c(a9.a,a9.d+r))
p=a0.$2(J.c(b0.a,b0.d+r),J.c(b1.a,b1.d+r))
o=a3+q+a4+p+524296
n=B.a.j(o+2*(q+a4),3)
m=B.a.j(o+2*(a3+p),3)
a5=B.a.j(n+a3,1)
l=B.a.j(m+q,1)
s=2*r
k=s-1
j=J.c(a6.a,a6.d+k)
i=a5&255
h=a5>>>16
g=k*4
f=A.o(b2,a,g)
j=19077*j
e=j+26149*h+-3644112
if((e&-4194304)>>>0===0)d=B.a.j(e,14)
else d=e<0?0:255
J.x(f.a,f.d,d)
h=j-6419*i-13320*h+2229552
if((h&-4194304)>>>0===0)d=B.a.j(h,14)
else d=h<0?0:255
J.x(f.a,f.d+1,d)
j=j+33050*i+-4527440
if((j&-4194304)>>>0===0)d=B.a.j(j,14)
else d=j<0?0:255
J.x(f.a,f.d+2,d)
J.x(f.a,f.d+3,255)
j=J.c(a6.a,a6.d+s)
i=l&255
h=l>>>16
f=s*4
e=A.o(b2,a,f)
j=19077*j
c=j+26149*h+-3644112
if((c&-4194304)>>>0===0)d=B.a.j(c,14)
else d=c<0?0:255
J.x(e.a,e.d,d)
h=j-6419*i-13320*h+2229552
if((h&-4194304)>>>0===0)d=B.a.j(h,14)
else d=h<0?0:255
J.x(e.a,e.d+1,d)
j=j+33050*i+-4527440
if((j&-4194304)>>>0===0)d=B.a.j(j,14)
else d=j<0?0:255
J.x(e.a,e.d+2,d)
J.x(e.a,e.d+3,255)
if(t){a5=B.a.j(m+a4,1)
l=B.a.j(n+p,1)
k=J.c(a7.a,a7.d+k)
j=a5&255
i=a5>>>16
b3.toString
g=A.o(b3,a,g)
k=19077*k
h=k+26149*i+-3644112
if((h&-4194304)>>>0===0)d=B.a.j(h,14)
else d=h<0?0:255
J.x(g.a,g.d,d)
i=k-6419*j-13320*i+2229552
if((i&-4194304)>>>0===0)d=B.a.j(i,14)
else d=i<0?0:255
J.x(g.a,g.d+1,d)
k=k+33050*j+-4527440
if((k&-4194304)>>>0===0)d=B.a.j(k,14)
else d=k<0?0:255
J.x(g.a,g.d+2,d)
J.x(g.a,g.d+3,255)
s=J.c(a7.a,a7.d+s)
k=l&255
j=l>>>16
f=A.o(b3,a,f)
s=19077*s
i=s+26149*j+-3644112
if((i&-4194304)>>>0===0)d=B.a.j(i,14)
else d=i<0?0:255
J.x(f.a,f.d,d)
j=s-6419*k-13320*j+2229552
if((j&-4194304)>>>0===0)d=B.a.j(j,14)
else d=j<0?0:255
J.x(f.a,f.d+1,d)
s=s+33050*k+-4527440
if((s&-4194304)>>>0===0)d=B.a.j(s,14)
else d=s<0?0:255
J.x(f.a,f.d+2,d)
J.x(f.a,f.d+3,255)}}if((b4&1)===0){a5=B.a.j(3*a3+a4+131074,2)
s=J.c(a6.a,a6.d+a1)
k=a1*4
j=A.o(b2,a,k)
b.d_(s,a5&255,a5>>>16,j)
j.i(0,3,255)
if(t){a5=B.a.j(3*a4+a3+131074,2)
a1=J.c(a7.a,a7.d+a1)
b3.toString
k=A.o(b3,a,k)
b.d_(a1,a5&255,a5>>>16,k)
k.i(0,3,255)}}},
hD(a,b,c){var t,s,r,q,p,o,n,m,l=this,k=l.xr
if(k==null)return
t=A.o(k,null,0)
if(a===0){s=c-1
r=a}else{r=a-1
t.d=t.d-l.b.a
s=c}k=l.Q
q=l.as
if(k+a+c===q)s=q-k-r
for(k=l.b,p=0;p<s;++p){for(q=p+r,o=0;o<b;++o){n=J.c(t.a,t.d+o)
m=l.d.a
m=m==null?null:m.L(o,q,null);(m==null?new A.G():m).su(n)}t.d=t.d+k.a}},
hE(a,b,a0){var t,s,r,q,p,o,n,m,l,k,j,i,h=this,g=null,f=J.V(h.d.gB(0),0,null),e=h.b.a,d=A.v(f,!1,g,a*e*4),c=h.to
c===$&&A.d()
t=A.o(c,g,0)
c=h.x1
c===$&&A.d()
s=A.o(c,g,0)
c=h.x2
c===$&&A.d()
r=A.o(c,g,0)
q=a+a0
p=B.a.j(b+1,1)
o=e*4
e=h.rx
e===$&&A.d()
n=A.o(e,g,0)
e=h.ry
e===$&&A.d()
m=A.o(e,g,0)
if(a===0){h.cZ(t,g,s,r,s,r,d,g,b)
l=a0}else{e=h.RG
e===$&&A.d()
h.cZ(e,t,n,m,s,r,A.o(d,g,-o),d,b)
l=a0+1}n.sB(0,s.a)
m.sB(0,r.a)
for(e=2*o,c=-o,k=a;k+=2,k<q;){n.d=s.d
m.d=r.d
j=s.d
i=h.R8
i.toString
s.d=j+i
r.d+=i
d.d+=e
i=t.d
j=h.p4
j.toString
t.d=i+2*j
h.cZ(A.o(t,g,-j),t,n,m,s,r,A.o(d,g,c),d,b)}e=t.d
c=h.p4
c.toString
t.d=e+c
if(h.Q+q<h.as){e=h.RG
e===$&&A.d()
e.bR(0,b,t)
h.rx.bR(0,p,s)
h.ry.bR(0,p,r);--l}else if((q&1)===0)h.cZ(t,g,s,r,s,r,A.o(d,g,o),g,b)
return l},
hy(a,b){var t,s,r,q,p,o,n,m,l,k=this,j=k.b,i=j.a,h=j.b
if(a<0||b<=0||a+b>h)return null
if(a===0){j=i*h
k.dH=new Uint8Array(j)
t=k.dG
s=new A.iD(t,i,h)
r=t.G()
q=s.d=r&3
s.e=B.a.j(r,2)&3
s.f=B.a.j(r,4)&3
s.r=B.a.j(r,6)&3
if(s.gf5())if(q===0){if(t.c-t.d<j)s.r=1}else if(q===1){p=new A.dg(B.a1,A.j([],u.J))
p.a=i
p.b=h
j=A.j([],u.F)
q=A.j([],u.R)
o=new Uint32Array(2)
n=new A.h7(t,o)
o=n.e=J.V(B.o.gB(o),0,null)
m=t.G()
o.$flags&2&&A.b(o)
if(0>=o.length)return A.a(o,0)
o[0]=m
m=t.G()
o.$flags&2&&A.b(o)
if(1>=o.length)return A.a(o,1)
o[1]=m
m=t.G()
o.$flags&2&&A.b(o)
if(2>=o.length)return A.a(o,2)
o[2]=m
m=t.G()
o.$flags&2&&A.b(o)
if(3>=o.length)return A.a(o,3)
o[3]=m
m=t.G()
o.$flags&2&&A.b(o)
if(4>=o.length)return A.a(o,4)
o[4]=m
m=t.G()
o.$flags&2&&A.b(o)
if(5>=o.length)return A.a(o,5)
o[5]=m
m=t.G()
o.$flags&2&&A.b(o)
if(6>=o.length)return A.a(o,6)
o[6]=m
t=t.G()
o.$flags&2&&A.b(o)
if(7>=o.length)return A.a(o,7)
o[7]=t
n.b=!1
q=new A.ft(n,p,j,q)
q.dy=i
q.fr=h
s.x=q
q.cd(i,h,!0)
j=s.x
t=j.ch
q=t.length
if(q===1){if(0>=q)return A.a(t,0)
j=t[0].a===B.cg&&j.hY()}else j=!1
if(j){s.y=!0
j=s.x
t=j.c
l=t.a*t.b
j.db=0
t=B.a.a1(l,4)
t=new Uint8Array(l+(4-t))
j.cy=t
j.cx=J.aw(B.e.gB(t),0,null)}else{s.y=!1
s.x.dZ(i)}}else s.r=1
k.f2=s}j=k.f2
if(j!=null)if(!j.w){t=k.dH
t===$&&A.d()
if(!j.j_(a,b,t))return null}j=k.dH
j===$&&A.d()
return A.v(j,!1,null,a*i)},
ia(a5,a6){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=this,a2=a1.fr.b,a3=a1.dy,a4=a1.k1
a4===$&&A.d()
if(!(a4<4))return A.a(a3,a4)
t=a3[a4]
a4=a1.co
a4===$&&A.d()
a3=a1.y1
if(!(a3<a4.length))return A.a(a4,a3)
s=a4[a3]
r=A.v(s.a,!1,null,0)
a3=a1.k3
a3===$&&A.d()
if(0>=a3.length)return A.a(a3,0)
q=a3[0]
r.jl(0,r.c-r.d,0)
a3=s.b
a3===$&&A.d()
if(!a3){p=A.v(new Int16Array(16),!1,null,0)
a3=a5.b
a4=q.b
if(1>=a2.length)return A.a(a2,1)
o=a1.dn(a6,a2[1],a3+a4,t.b,0,p)
a5.b=q.b=o>0?1:0
if(o>1)a1.iO(p,r)
else{n=B.a.j(J.c(p.a,p.d)+3,3)
for(m=0;m<256;m+=16)J.x(r.a,r.d+m,n)}l=a2[0]
k=1}else{if(3>=a2.length)return A.a(a2,3)
l=a2[3]
k=0}j=a5.a&15
i=q.a&15
for(h=0,g=0;g<4;++g){f=i&1
for(e=0,d=0;d<4;++d){o=a1.dn(a6,l,f+(j&1),t.a,k,r)
f=o>k?1:0
j=j>>>1|f<<7
a3=J.c(r.a,r.d)!==0?1:0
if(o>3)a3=3
else if(o>1)a3=2
e=e<<2|a3
r.d+=16}j=j>>>4
i=i>>>1|f<<7
h=(h<<8|e)>>>0}c=i>>>4
for(a3=a2.length,b=j,a=0,a0=0;a0<4;a0+=2){a4=4+a0
j=B.a.a_(a5.a,a4)
i=B.a.a_(q.a,a4)
for(e=0,g=0;g<2;++g){f=i&1
for(d=0;d<2;++d){if(2>=a3)return A.a(a2,2)
o=a1.dn(a6,a2[2],f+(j&1),t.c,0,r)
f=o>0?1:0
j=j>>>1|f<<3
a4=J.c(r.a,r.d)!==0?1:0
if(o>3)a4=3
else if(o>1)a4=2
e=(e<<2|a4)>>>0
r.d+=16}j=j>>>2
i=i>>>1|f<<5}a=(a|B.a.O(e,4*a0))>>>0
b=(b|B.a.O(j<<4>>>0,a0))>>>0
c=(c|B.a.O(i&240,a0))>>>0}a5.a=b
q.a=c
s.e=h
s.f=a
if((a&43690)===0)t.toString
return(h|a)>>>0===0},
iO(a,b){var t,s,r,q,p,o,n,m,l,k,j=new Int32Array(16)
for(t=0;t<4;++t){s=12+t
r=J.c(a.a,a.d+t)+J.c(a.a,a.d+s)
q=4+t
p=8+t
o=J.c(a.a,a.d+q)+J.c(a.a,a.d+p)
n=J.c(a.a,a.d+q)-J.c(a.a,a.d+p)
m=J.c(a.a,a.d+t)-J.c(a.a,a.d+s)
if(!(t<16))return A.a(j,t)
j[t]=r+o
if(!(p<16))return A.a(j,p)
j[p]=r-o
j[q]=m+n
if(!(s<16))return A.a(j,s)
j[s]=m-n}for(l=0,t=0;t<4;++t){s=t*4
if(!(s<16))return A.a(j,s)
k=j[s]+3
q=3+s
if(!(q<16))return A.a(j,q)
q=j[q]
r=k+q
p=1+s
if(!(p<16))return A.a(j,p)
p=j[p]
s=2+s
if(!(s<16))return A.a(j,s)
s=j[s]
o=p+s
n=p-s
m=k-q
q=B.a.j(r+o,3)
J.x(b.a,b.d+l,q)
q=B.a.j(m+n,3)
J.x(b.a,b.d+(l+16),q)
q=B.a.j(r-o,3)
J.x(b.a,b.d+(l+32),q)
q=B.a.j(m-n,3)
J.x(b.a,b.d+(l+48),q)
l+=64}},
hQ(a,b){var t,s,r,q,p,o,n
u.L.a(b)
if(a.a7(b[3])===0)t=a.a7(b[4])===0?2:3+a.a7(b[5])
else if(a.a7(b[6])===0)t=a.a7(b[7])===0?5+a.a7(159):7+2*a.a7(165)+a.a7(145)
else{s=a.a7(b[8])
r=9+s
if(!(r<11))return A.a(b,r)
q=2*s+a.a7(b[r])
if(!(q<4))return A.a(B.be,q)
p=B.be[q]
o=p.length
for(t=0,n=0;n<o;++n)t+=t+a.a7(p[n])
t+=3+B.a.O(8,q)}return t},
dn(a,b,c,d,e,f){var t,s,r,q,p,o,n,m,l,k
u.B.a(b)
u.L.a(d)
t=b.length
if(!(e<t))return A.a(b,e)
s=b[e].a
if(!(c<s.length))return A.a(s,c)
r=s[c]
for(;e<16;e=q){if(a.a7(r[0])===0)return e
while(a.a7(r[1])===0){s=$.kN();++e
if(!(e>=0&&e<s.length))return A.a(s,e)
s=s[e]
if(!(s<t))return A.a(b,s)
s=b[s].a
if(0>=s.length)return A.a(s,0)
r=s[0]
if(e===16)return 16}s=$.kN()
q=e+1
if(!(q>=0&&q<s.length))return A.a(s,q)
s=s[q]
if(!(s<t))return A.a(b,s)
p=b[s].a
s=p.length
if(a.a7(r[2])===0){if(1>=s)return A.a(p,1)
r=p[1]
o=1}else{o=this.hQ(a,r)
if(2>=s)return A.a(p,2)
r=p[2]}s=$.mJ()
if(!(e>=0&&e<s.length))return A.a(s,e)
s=s[e]
n=a.b
n===$&&A.d()
m=a.e0(B.a.j(n,1))
n=a.b
if(n>>>0!==n||n>=128)return A.a(B.ab,n)
l=B.ab[n]
a.b=B.bE[n]
n=a.d
n===$&&A.d()
a.d=n-l
n=m!==0?-o:o
k=d[e>0?1:0]
J.x(f.a,f.d+s,n*k)}return 16},
i6(){var t,s,r,q,p,o,n,m,l,k,j=this,i=j.y1,h=4*i,g=j.go,f=j.id,e=j.co
e===$&&A.d()
if(!(i<e.length))return A.a(e,i)
t=e[i]
i=j.c
i===$&&A.d()
i=i.a7(145)===0
t.b=i
if(!i){if(j.c.a7(156)!==0)s=j.c.a7(128)!==0?1:3
else s=j.c.a7(163)!==0?2:0
i=t.c
i.$flags&2&&A.b(i)
i[0]=s
g.toString
B.e.aB(g,h,h+4,s)
B.e.aB(f,0,4,s)}else{r=t.c
for(q=0,p=0;p<4;++p,q=k){s=f[p]
for(o=0;o<4;++o){i=h+o
if(!(i<g.length))return A.a(g,i)
e=g[i]
if(!(e<10))return A.a(B.bz,e)
e=B.bz[e]
if(!(s>=0&&s<10))return A.a(e,s)
n=e[s]
m=j.c.a7(n[0])
if(!(m<18))return A.a(B.a9,m)
l=B.a9[m]
while(l>0){e=j.c
if(!(l<9))return A.a(n,l)
e=2*l+e.a7(n[l])
if(!(e>=0&&e<18))return A.a(B.a9,e)
l=B.a9[e]}s=-l
g.$flags&2&&A.b(g)
g[i]=s}k=q+4
g.toString
B.e.ar(r,q,k,g,h)
f.$flags&2&&A.b(f)
if(!(p<4))return A.a(f,p)
f[p]=s}}if(j.c.a7(142)===0)i=0
else if(j.c.a7(114)===0)i=2
else i=j.c.a7(183)!==0?1:3
t.d=i}}
A.iC.prototype={
$2(a,b){return(a|b<<16)>>>0},
$S:29}
A.eu.prototype={
X(a){var t,s
for(t=0;s=a-1,a>0;a=s)t=(t|B.a.W(this.a7(128),s))>>>0
return t},
cb(a){var t=this.X(a)
return this.X(1)===1?-t:t},
a7(a){var t,s=this,r=s.b
r===$&&A.d()
t=s.e0(B.a.j(r*a,8))
if(s.b<=126)s.iM()
return t},
e0(a){var t,s,r,q,p,o=this,n=o.d
n===$&&A.d()
if(n<0){t=o.a
s=t.c
r=t.d
if(s-r>=1){q=t.G()
n=o.c
n===$&&A.d()
o.c=(q|n<<8)>>>0
n=o.d+8
o.d=n
p=n}else{if(r<s){n=t.G()
t=o.c
t===$&&A.d()
o.c=(n|t<<8)>>>0
t=o.d+8
o.d=t
n=t}else if(!o.e){t=o.c
t===$&&A.d()
o.c=t<<8>>>0
n+=8
o.d=n
o.e=!0}p=n}}else p=n
n=o.c
n===$&&A.d()
if(B.a.bs(n,p)>a){t=o.b
t===$&&A.d()
s=a+1
o.b=t-s
o.c=n-B.a.W(s,p)
return 1}else{o.b=a
return 0}},
iM(){var t,s=this,r=s.b
r===$&&A.d()
if(!(r>=0&&r<128))return A.a(B.ab,r)
t=B.ab[r]
s.b=B.bE[r]
r=s.d
r===$&&A.d()
s.d=r-t}}
A.ir.prototype={
dQ(a,b,c){var t,s=A.o(a,null,0)
for(t=0;t<16;++t){s.d=a.d+t
if(this.er(s,b,c))this.cP(s,b)}},
dP(a,b,c){var t,s=A.o(a,null,0)
for(t=0;t<16;++t){s.d=a.d+t*b
if(this.er(s,1,c))this.cP(s,1)}},
fw(a,b,c){var t,s,r=A.o(a,null,0)
for(t=4*b,s=3;s>0;--s){r.d+=t
this.dQ(r,b,c)}},
fv(a,b,c){var t,s=A.o(a,null,0)
for(t=3;t>0;--t){s.d+=4
this.dP(s,b,c)}},
jC(a,b,c,d,e){var t,s,r=A.o(a,null,0)
for(t=4*b,s=3;s>0;--s){r.d+=t
this.c6(r,b,1,16,c,d,e)}},
jd(a,b,c,d,e){var t,s=A.o(a,null,0)
for(t=3;t>0;--t){s.d+=4
this.c6(s,1,b,16,c,d,e)}},
c7(a,b,a0,a1,a2,a3,a4){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=A.o(a,null,0)
for(t=-3*b,s=-2*b,r=-b,q=2*b;p=a1-1,a1>0;a1=p){if(this.es(c,b,a2,a3))if(this.en(c,b,a4))this.cP(c,b)
else{o=J.c(c.a,c.d+t)
n=J.c(c.a,c.d+s)
m=J.c(c.a,c.d+r)
l=J.c(c.a,c.d)
k=J.c(c.a,c.d+b)
j=J.c(c.a,c.d+q)
i=$.jH()
h=1020+n-k
if(!(h>=0&&h<2041))return A.a(i,h)
h=1020+3*(l-m)+i[h]
if(!(h>=0&&h<2041))return A.a(i,h)
g=i[h]
h=B.a.j(27*g+63,7)
f=(h&2147483647)-((h&2147483648)>>>0)
h=B.a.j(18*g+63,7)
e=(h&2147483647)-((h&2147483648)>>>0)
h=B.a.j(9*g+63,7)
d=(h&2147483647)-((h&2147483648)>>>0)
h=$.aB()
i=255+o+d
if(!(i>=0&&i<766))return A.a(h,i)
i=h[i]
J.x(c.a,c.d+t,i)
i=$.aB()
h=255+n+e
if(!(h>=0&&h<766))return A.a(i,h)
h=i[h]
J.x(c.a,c.d+s,h)
h=$.aB()
i=255+m+f
if(!(i>=0&&i<766))return A.a(h,i)
i=h[i]
J.x(c.a,c.d+r,i)
i=$.aB()
h=255+l-f
if(!(h>=0&&h<766))return A.a(i,h)
h=i[h]
J.x(c.a,c.d,h)
h=$.aB()
i=255+k-e
if(!(i>=0&&i<766))return A.a(h,i)
i=h[i]
J.x(c.a,c.d+b,i)
i=$.aB()
h=255+j-d
if(!(h>=0&&h<766))return A.a(i,h)
h=i[h]
J.x(c.a,c.d+q,h)}c.d+=a0}},
c6(a,b,c,d,e,f,a0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=A.o(a,null,0)
for(t=-2*b,s=-b;r=d-1,d>0;d=r){if(this.es(g,b,e,f))if(this.en(g,b,a0))this.cP(g,b)
else{q=J.c(g.a,g.d+t)
p=J.c(g.a,g.d+s)
o=J.c(g.a,g.d)
n=J.c(g.a,g.d+b)
m=3*(o-p)
l=$.jI()
k=B.a.j(m+4,3)
k=112+((k&2147483647)-((k&2147483648)>>>0))
if(!(k>=0&&k<225))return A.a(l,k)
j=l[k]
k=B.a.j(m+3,3)
k=112+((k&2147483647)-((k&2147483648)>>>0))
if(!(k>=0&&k<225))return A.a(l,k)
i=l[k]
k=B.a.j(j+1,1)
h=(k&2147483647)-((k&2147483648)>>>0)
k=$.aB()
l=255+q+h
if(!(l>=0&&l<766))return A.a(k,l)
l=k[l]
J.x(g.a,g.d+t,l)
l=$.aB()
k=255+p+i
if(!(k>=0&&k<766))return A.a(l,k)
k=l[k]
J.x(g.a,g.d+s,k)
k=$.aB()
l=255+o-j
if(!(l>=0&&l<766))return A.a(k,l)
l=k[l]
J.x(g.a,g.d,l)
l=$.aB()
k=255+n-h
if(!(k>=0&&k<766))return A.a(l,k)
k=l[k]
J.x(g.a,g.d+b,k)}g.d+=c}},
cP(a,b){var t,s,r,q=J.c(a.a,a.d+-2*b),p=-b,o=J.c(a.a,a.d+p),n=J.c(a.a,a.d),m=J.c(a.a,a.d+b),l=$.jH(),k=1020+q-m
if(!(k>=0&&k<2041))return A.a(l,k)
t=3*(n-o)+l[k]
k=$.jI()
l=112+B.a.aq(B.a.j(t+4,3),32)
if(!(l>=0&&l<225))return A.a(k,l)
s=k[l]
l=112+B.a.aq(B.a.j(t+3,3),32)
if(!(l>=0&&l<225))return A.a(k,l)
r=k[l]
l=$.aB()
k=255+o+r
if(!(k>=0&&k<766))return A.a(l,k)
a.i(0,p,l[k])
k=$.aB()
l=255+n-s
if(!(l>=0&&l<766))return A.a(k,l)
a.i(0,0,k[l])},
en(a,b,c){var t=J.c(a.a,a.d+-2*b),s=J.c(a.a,a.d+-b),r=J.c(a.a,a.d),q=J.c(a.a,a.d+b),p=$.hp(),o=255+t-s
if(!(o>=0&&o<511))return A.a(p,o)
if(p[o]<=c){o=255+q-r
if(!(o>=0&&o<511))return A.a(p,o)
o=p[o]>c
p=o}else p=!0
return p},
er(a,b,c){var t,s=J.c(a.a,a.d+-2*b),r=J.c(a.a,a.d+-b),q=J.c(a.a,a.d),p=J.c(a.a,a.d+b),o=$.hp(),n=255+r-q
if(!(n>=0&&n<511))return A.a(o,n)
n=o[n]
o=$.jG()
t=255+s-p
if(!(t>=0&&t<511))return A.a(o,t)
return 2*n+o[t]<=c},
es(a,b,c,d){var t,s,r,q=J.c(a.a,a.d+-4*b),p=J.c(a.a,a.d+-3*b),o=J.c(a.a,a.d+-2*b),n=J.c(a.a,a.d+-b),m=J.c(a.a,a.d),l=J.c(a.a,a.d+b),k=J.c(a.a,a.d+2*b),j=J.c(a.a,a.d+3*b),i=$.hp(),h=255+n-m
if(!(h>=0&&h<511))return A.a(i,h)
h=i[h]
t=$.jG()
s=255+o
r=s-l
if(!(r>=0&&r<511))return A.a(t,r)
if(2*h+t[r]>c)return!1
h=255+q-p
if(!(h>=0&&h<511))return A.a(i,h)
t=!1
if(i[h]<=d){h=255+p-o
if(!(h>=0&&h<511))return A.a(i,h)
if(i[h]<=d){h=s-n
if(!(h>=0&&h<511))return A.a(i,h)
if(i[h]<=d){h=255+j-k
if(!(h>=0&&h<511))return A.a(i,h)
if(i[h]<=d){h=255+k-l
if(!(h>=0&&h<511))return A.a(i,h)
if(i[h]<=d){h=255+l-m
if(!(h>=0&&h<511))return A.a(i,h)
h=i[h]<=d
i=h}else i=t}else i=t}else i=t}else i=t}else i=t
return i},
bz(a,b){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=new Int32Array(16)
for(t=0,s=0,r=0;r<4;++r){q=t+8
p=J.c(a.a,a.d+t)+J.c(a.a,a.d+q)
o=J.c(a.a,a.d+t)-J.c(a.a,a.d+q)
q=t+4
n=B.a.j(J.c(a.a,a.d+q)*35468,16)
m=t+12
l=B.a.j(J.c(a.a,a.d+m)*85627,16)
k=(n&2147483647)-((n&2147483648)>>>0)-((l&2147483647)-((l&2147483648)>>>0))
q=B.a.j(J.c(a.a,a.d+q)*85627,16)
m=B.a.j(J.c(a.a,a.d+m)*35468,16)
j=(q&2147483647)-((q&2147483648)>>>0)+((m&2147483647)-((m&2147483648)>>>0))
i=s+1
if(!(s<16))return A.a(f,s)
f[s]=p+j
s=i+1
if(!(i<16))return A.a(f,i)
f[i]=o+k
i=s+1
if(!(s<16))return A.a(f,s)
f[s]=o-k
s=i+1
if(!(i<16))return A.a(f,i)
f[i]=p-j;++t}for(h=0,s=0,r=0;r<4;++r){if(!(s<16))return A.a(f,s)
g=f[s]+4
q=s+8
if(!(q<16))return A.a(f,q)
q=f[q]
p=g+q
o=g-q
q=s+4
if(!(q<16))return A.a(f,q)
q=f[q]
n=B.a.j(q*35468,16)
m=s+12
if(!(m<16))return A.a(f,m)
m=f[m]
l=B.a.j(m*85627,16)
k=(n&2147483647)-((n&2147483648)>>>0)-((l&2147483647)-((l&2147483648)>>>0))
q=B.a.j(q*85627,16)
m=B.a.j(m*35468,16)
j=(q&2147483647)-((q&2147483648)>>>0)+((m&2147483647)-((m&2147483648)>>>0))
A.bH(b,h,0,0,p+j)
A.bH(b,h,1,0,o+k)
A.bH(b,h,2,0,o-k)
A.bH(b,h,3,0,p-j);++s
h+=32}},
jz(a,b,c){this.bz(a,b)
if(c)this.bz(A.o(a,null,16),A.o(b,null,4))},
cA(a,b){var t,s,r=J.c(a.a,a.d)+4
for(t=0;t<4;++t)for(s=0;s<4;++s)A.bH(b,0,s,t,r)},
fh(a,b){var t=this,s=null
if(J.c(a.a,a.d)!==0)t.cA(a,b)
if(J.c(a.a,a.d+16)!==0)t.cA(A.o(a,s,16),A.o(b,s,4))
if(J.c(a.a,a.d+32)!==0)t.cA(A.o(a,s,32),A.o(b,s,128))
if(J.c(a.a,a.d+48)!==0)t.cA(A.o(a,s,48),A.o(b,s,132))}}
A.iw.prototype={}
A.iz.prototype={}
A.iB.prototype={}
A.et.prototype={}
A.iA.prototype={}
A.is.prototype={}
A.bq.prototype={}
A.ew.prototype={}
A.h9.prototype={}
A.ex.prototype={}
A.ey.prototype={}
A.ev.prototype={
cn(){var t,s,r,q,p=this,o=p.b
if(o.af(8)!==47)return!1
t=o.af(14)+1
s=o.af(14)+1
r=o.af(1)
p.dy=t
p.fr=s
q=p.c
q.f=B.al
q.a=t
q.b=s
q.d=r!==0
if(o.af(3)!==0)return!1
return!0},
bF(){var t,s,r,q,p,o,n=this,m=null
n.f=0
if(!n.cn())return m
n.cd(n.dy,n.fr,!0)
n.dZ(n.dy)
t=n.dy
n.d=A.R(m,m,B.f,0,B.j,n.fr,m,0,4,m,B.f,t,!1)
t=n.cx
t.toString
s=n.c
r=s.a
q=s.b
if(!n.dg(t,r,q,q,n.gih()))return m
t=s.w
if(t.length!==0){p=A.v(new A.aJ(t),!1,m,0)
t=n.d
t.toString
t.e=A.jP(p)}o=s.r
if(o!=null)n.d.c=new A.bf("",B.P,o)
return n.d},
dZ(a){var t,s=this,r=s.c
r=r.a*r.b+a
t=new Uint32Array(r+a*16)
s.cx=t
s.cy=J.V(B.o.gB(t),0,null)
s.db=r
return!0},
iI(a){var t,s,r,q,p,o,n,m=this
u.L.a(a)
t=m.b
s=t.af(2)
r=m.CW
q=B.a.O(1,s)
if((r&q)>>>0!==0)return!1
m.CW=(r|q)>>>0
p=new A.h8(B.cf)
B.c.A(m.ch,p)
if(!(s<4))return A.a(B.bK,s)
r=B.bK[s]
p.a=r
p.b=a[0]
p.c=a[1]
switch(r.a){case 0:case 1:t=t.af(3)+2
p.e=t
p.d=m.cd(A.bI(p.b,t),A.bI(p.c,p.e),!1)
break
case 3:o=t.af(8)+1
if(o>16)n=0
else if(o>4)n=1
else{t=o>2?2:3
n=t}B.c.i(a,0,A.bI(p.b,n))
p.e=n
p.d=m.cd(o,1,!1)
m.hH(o,p)
break
case 2:break}return!0},
cd(a,b,c){var t,s,r,q,p,o,n,m,l=this
if(c)for(t=l.b,s=u.t,r=b,q=a;t.af(1)!==0;){p=A.j([q,r],s)
if(!l.iI(p))throw A.f(A.n("Invalid Transform"))
q=p[0]
r=p[1]}else{r=b
q=a}t=l.b
if(t.af(1)!==0){o=t.af(4)
if(!(o>=1&&o<=11))throw A.f(A.n("Invalid Color Cache"))}else o=0
if(!l.iv(q,r,o,c))throw A.f(A.n("Invalid Huffman Codes"))
if(o>0){t=B.a.O(1,o)
l.w=t
l.x=new A.ix(new Uint32Array(t),32-o)}else l.w=0
t=l.c
t.a=q
t.b=r
n=l.z
l.Q=A.bI(q,n)
l.y=n===0?4294967295:B.a.O(1,n)-1
if(c){l.f=0
return null}m=new Uint32Array(q*r)
if(!l.dg(m,q,r,r,null))throw A.f(A.n("Failed to decode image data."))
l.f=0
return m},
dg(b5,b6,b7,b8,b9){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3=this,b4=506832829
u.e7.a(b9)
t=b3.f
s=B.a.au(t,b6)
r=B.a.a1(t,b6)
q=b6*b7
p=b6*b8
if(t>=p){if(b9!=null)b9.$2(b8,!1)
return!0}o=b3.eg(r,s)
n=b3.w
m=280+n
l=n>0?b3.x:null
k=b3.y
for(n=b5.length,j=b3.b,i=b9!=null,h=b5.$flags|0,g=t;g<p;){if((r&k)>>>0===0){f=b3.cf(b3.as,b3.Q,b3.z,r,s)
e=b3.ax
if(!(f<e.length))return A.a(e,f)
o=e[f]}d=0
if(o.d){e=o.c
h&2&&A.b(b5)
if(!(g>=0&&g<n))return A.a(b5,g)
b5[g]=e;++g;++r
if(r>=b6){++s
if(i&&s<=b8)b9.$2(s,!0)
if(l!=null)for(e=l.a,c=l.b,b=e.$flags|0;t<g;){if(!(t>=0&&t<n))return A.a(b5,t)
a=b5[t]
a0=B.a.a0(A.eN(a,b4),c)
b&2&&A.b(e)
if(!(a0<e.length))return A.a(e,a0)
e[a0]=a;++t}r=d}continue}if(j.a>=32)j.c0()
if(o.e){a1=j.cu()&63
e=o.f
if(!(a1<e.length))return A.a(e,a1)
a2=e[a1]
e=a2.a
c=j.a
if(e<256){j.a=c+e
e=a2.b
h&2&&A.b(b5)
if(!(g>=0&&g<n))return A.a(b5,g)
b5[g]=e
a3=0}else{j.a=c+(e-256)
a3=a2.b}if(j.b)break
if(a3===0){++g;++r
if(r>=b6){++s
if(i&&s<=b8)b9.$2(s,!0)
if(l!=null)for(e=l.a,c=l.b,b=e.$flags|0;t<g;){if(!(t>=0&&t<n))return A.a(b5,t)
a=b5[t]
a0=B.a.a0(A.eN(a,b4),c)
b&2&&A.b(e)
if(!(a0<e.length))return A.a(e,a0)
e[a0]=a;++t}r=d}continue}}else a3=o.c4(0,j)
if(a3<256){if(o.b){e=o.c
h&2&&A.b(b5)
if(!(g>=0&&g<n))return A.a(b5,g)
b5[g]=(e|a3<<8)>>>0}else{a4=o.c4(1,j)
if(j.a>=32)j.c0()
a5=A.mm(o.c4(2,j),a3,a4,o.c4(3,j))
h&2&&A.b(b5)
if(!(g>=0&&g<n))return A.a(b5,g)
b5[g]=a5}++g;++r
if(r>=b6){++s
if(i&&s<=b8)b9.$2(s,!0)
if(l!=null)for(e=l.a,c=l.b,b=e.$flags|0;t<g;){if(!(t>=0&&t<n))return A.a(b5,t)
a=b5[t]
a0=B.a.a0(A.eN(a,b4),c)
b&2&&A.b(e)
if(!(a0<e.length))return A.a(e,a0)
e[a0]=a;++t}r=d}}else if(a3<280){a6=b3.cS(a3-256)
a7=o.c4(4,j)
if(j.a>=32)j.c0()
a8=b3.ev(b6,b3.cS(a7))
if(g<a8||q-g<a6)return!1
else{a9=g-a8
for(b0=0;b0<a6;++b0){e=g+b0
c=a9+b0
if(!(c>=0&&c<n))return A.a(b5,c)
c=b5[c]
h&2&&A.b(b5)
if(!(e>=0&&e<n))return A.a(b5,e)
b5[e]=c}}g+=a6
r+=a6
while(r>=b6){r-=b6;++s
if(i&&s<=b8)b9.$2(s,!0)}if((r&k)>>>0!==0){f=b3.cf(b3.as,b3.Q,b3.z,r,s)
e=b3.ax
if(!(f<e.length))return A.a(e,f)
o=e[f]}if(l!=null)for(e=l.a,c=l.b,b=e.$flags|0;t<g;){if(!(t>=0&&t<n))return A.a(b5,t)
a=b5[t]
a0=B.a.a0(A.eN(a,b4),c)
b&2&&A.b(e)
if(!(a0<e.length))return A.a(e,a0)
e[a0]=a;++t}}else if(a3<m){b1=a3-280
while(t<g){l.toString
if(!(t>=0&&t<n))return A.a(b5,t)
e=b5[t]
c=l.a
b=B.a.a0(A.eN(e,b4),l.b)
c.$flags&2&&A.b(c)
if(!(b<c.length))return A.a(c,b)
c[b]=e;++t}e=l.a
c=e.length
if(!(b1<c))return A.a(e,b1)
b=e[b1]
h&2&&A.b(b5)
if(!(g>=0&&g<n))return A.a(b5,g)
b5[g]=b;++g;++r
if(r>=b6){++s
if(i&&s<=b8)b9.$2(s,!0)
for(b=l.b,a=e.$flags|0;t<g;){if(!(t>=0&&t<n))return A.a(b5,t)
a0=b5[t]
b2=B.a.a0(A.eN(a0,b4),b)
a&2&&A.b(e)
if(!(b2<c))return A.a(e,b2)
e[b2]=a0;++t}r=d}}else return!1}if(i)b9.$2(s>b8?b8:s,!1)
b3.f=g
return!0},
hY(){var t,s,r,q,p,o,n,m
if(this.w>0)return!1
for(t=this.at,s=this.ax,r=s.length,q=0;q<t;++q){if(!(q<r))return A.a(s,q)
p=s[q].a
o=p.length
if(1>=o)return A.a(p,1)
n=p[1]
m=n.a
n=n.b
if(!(n<m.length))return A.a(m,n)
if(m[n].a>0)return!1
if(2>=o)return A.a(p,2)
n=p[2]
m=n.a
n=n.b
if(!(n<m.length))return A.a(m,n)
if(m[n].a>0)return!1
if(3>=o)return A.a(p,3)
o=p[3]
n=o.a
o=o.b
if(!(o<n.length))return A.a(n,o)
if(n[o].a>0)return!1}return!0},
hI(a,b){var t,s,r,q,p,o,n,m,l,k,j,i,h=this
if(b&&B.a.a1(a,16)!==0)return
t=h.r
s=a-t
r=h.dy
q=r*t
while(s>0){p=s>16?16:s
o=r*p
n=r*t
m=h.db
h.e_(t,p,q)
for(r=h.dx,l=h.cx,k=0;k<o;++k){r.toString
j=n+k
i=m+k
if(!(i<l.length))return A.a(l,i)
i=l[i]
r.$flags&2&&A.b(r)
if(!(j>=0&&j<r.length))return A.a(r,j)
r[j]=i>>>8&255}s-=p
r=h.dy
q+=p*r
t+=p}h.r=a},
hg(a,a0,a1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g=this,f=g.f,e=B.a.au(f,a),d=B.a.a1(f,a),c=a*a0,b=a*a1
if(f>=b){g.cQ(e)
return!0}t=g.eg(d,e)
s=g.y
r=g.b
for(;;){if(!(!r.b&&f<b))break
if((d&s)>>>0===0){q=g.cf(g.as,g.Q,g.z,d,e)
p=g.ax
if(!(q<p.length))return A.a(p,q)
t=p[q]}if(r.a>=32)r.c0()
o=t.c4(0,r)
if(o<256){p=g.cy
p===$&&A.d()
p.$flags&2&&A.b(p)
if(!(f>=0&&f<p.length))return A.a(p,f)
p[f]=o;++f;++d
if(d>=a){++e
if(B.a.a1(e,16)===0)g.cQ(e)
d=0}}else if(o<280){n=g.cS(o-256)
m=t.c4(4,r)
if(r.a>=32)r.c0()
l=g.ev(a,g.cS(m))
if(f>=l&&c-f>=n)for(p=g.cy,k=0;k<n;++k){p===$&&A.d()
j=f+k
i=j-l
h=p.length
if(!(i>=0&&i<h))return A.a(p,i)
i=p[i]
p.$flags&2&&A.b(p)
if(!(j>=0&&j<h))return A.a(p,j)
p[j]=i}else{g.f=f
return!0}f+=n
d+=n
while(d>=a){d-=a;++e
if(B.a.a1(e,16)===0)g.cQ(e)}if(f<b&&(d&s)>>>0!==0){q=g.cf(g.as,g.Q,g.z,d,e)
p=g.ax
if(!(q<p.length))return A.a(p,q)
t=p[q]}}else return!1}g.cQ(e)
g.f=f
return!0},
cQ(a){var t,s,r=this,q=r.r,p=a-q,o=r.cy
o===$&&A.d()
t=A.v(o,!1,null,r.c.a*q)
if(p>0){o=r.dx
o.toString
s=A.v(o,!1,null,r.dy*q)
o=r.ch
if(0>=o.length)return A.a(o,0)
o[0].iV(q,q+p,t,s)}r.r=a},
ii(a,b){var t,s,r,q,p,o,n=this,m=n.c.a,l=n.r
if(b)if(B.a.a1(a,16)!==0)return
t=a-l
if(t<=0){n.r=a
return}n.e_(l,t,m*l)
for(s=n.db,r=n.r,q=0;q<t;++q,++r)for(p=0;p<n.dy;++p,++s){m=n.cx
if(!(s>=0&&s<m.length))return A.a(m,s)
o=m[s]
m=n.d.a
if(m!=null)m.ak(p,r,o>>>16&255,o>>>8&255,o&255,o>>>24&255)}n.r=a},
e_(a,b,c){var t,s=this,r=s.ch,q=r.length,p=s.c.a,o=a+b,n=s.db,m=s.cx
m.toString
B.o.ar(m,n,n+p*b,m,c)
for(;t=q-1,q>0;q=t){if(!(t>=0&&t<r.length))return A.a(r,t)
p=r[t]
m=s.cx
m.toString
p.jk(a,o,m,n,m,n)}},
iv(a,b,c,a0){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f=this,e=1,d=null
if(a0&&f.b.af(1)!==0){t=2+f.b.af(3)
s=A.bI(a,t)
r=A.bI(b,t)
q=s*r
p=f.cd(s,r,!1)
if(p==null)return!1
f.z=t
for(o=p.length,n=p.$flags|0,m=e,l=0;l<q;++l){if(!(l<o))return A.a(p,l)
k=p[l]>>>8&65535
n&2&&A.b(p)
p[l]=k
if(k>=m)m=k+1}if(m>1000||m>a*b){d=new Int32Array(1)
B.X.aB(d,0,1,255)
for(e=0,l=0;l<q;++l){if(!(l<o))return A.a(p,l)
j=p[l]
if(!(j<1))return A.a(d,j)
if(d[j]===-1){i=e+1
d[j]=e
e=i}h=d[j]
n&2&&A.b(p)
p[l]=h}}else e=m}else{p=null
m=1}if(f.b.b)return!1
g=f.iw(c,e,m,d)
if(g==null)return!1
f.as=p
f.at=e
f.ax=g
return!0},
dB(a,b,c,d,e,f){var t,s=a.a,r=a.b,q=d
do{q-=c
t=r+(b+q)
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
t.a=e
t.b=f}while(q>0)},
i0(a,b,c){var t=B.a.W(1,b-c)
while(b<15){t-=a[b]
if(t<=0)break;++b
t=t<<1>>>0}return b-c},
ek(a,b){var t=B.a.W(1,b-1)
while((a&t)>>>0!==0)t=t>>>1
return t!==0?((a&t-1)>>>0)+t:a},
e1(a4,a5,a6,a7,a8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=this,a1=B.a.O(1,a5),a2=new Int32Array(16),a3=new Int32Array(16)
for(t=a6.length,s=0;s<a7;++s){if(!(s<t))return A.a(a6,s)
r=a6[s]
if(r>15)return 0
if(!(r>=0))return A.a(a2,r)
a2[r]=a2[r]+1}if(a2[0]===a7)return 0
a3[1]=0
for(q=1;q<15;q=p){r=a2[q]
if(r>B.a.O(1,q))return 0
p=q+1
a3[p]=a3[q]+r}for(r=a8!=null,s=0;s<a7;++s){if(!(s<t))return A.a(a6,s)
o=a6[s]
if(o>0)if(r){if(!(o<16))return A.a(a3,o)
n=a3[o]
if(n>=a7)return 0
a3[o]=n+1
a8.$flags&2&&A.b(a8)
if(!(n>=0&&n<a8.length))return A.a(a8,n)
a8[n]=s}else{if(!(o<16))return A.a(a3,o)
a3[o]=a3[o]+1}}if(a3[15]===1){if(r){a4.toString
if(0>=a8.length)return A.a(a8,0)
a0.dB(a4,0,1,a1,0,a8[0])}return a1}m=a1-1
for(t=a4==null,l=0,k=1,j=1,s=0,q=1,i=2;q<=a5;++q,i=i<<1>>>0){j=j<<1>>>0
k+=j
if(!(q<16))return A.a(a2,q)
j-=a2[q]
if(j<0)return 0
if(t)continue
for(h=q&255;a2[q]>0;a2[q]=a2[q]-1,s=g){g=s+1
if(!(s>=0&&s<a8.length))return A.a(a8,s)
a0.dB(a4,l,i,a1,h,a8[s])
l=a0.ek(l,q)}}for(q=a5+1,t=!t,f=a1,e=0,d=4294967295,i=2;q<=15;++q,i=i<<1>>>0){j=j<<1>>>0
k+=j
j-=a2[q]
if(j<0)return 0
for(h=q-a5&255;a2[q]>0;a2[q]=a2[q]-1){c=(l&m)>>>0
if(c!==d){if(t)e+=f
b=a0.i0(a2,q,a5)
f=B.a.W(1,b)
a1+=f
if(t){r=a4.a
n=a4.b+c
if(!(n>=0&&n<r.length))return A.a(r,n)
n=r[n]
n.a=b+a5&255
n.b=e-c}d=c}if(t){g=s+1
if(!(s>=0&&s<a8.length))return A.a(a8,s)
a=a8[s]
a0.dB(a4,e+B.a.a_(l,a5),i,f,h,a)
s=g}l=a0.ek(l,q)}}if(k!==2*a3[15]-1)return 0
return a1},
eI(a,b,c,d){var t,s,r,q,p,o,n=this.e1(null,b,c,d,null)
if(n===0||a==null)return n
t=a.b
s=t.d
r=t.e
if(s+n>=r){q=new A.dB()
if(n>r)r=n
p=A.jT(r)
q.e=r
q.b=q.a=p
a.b=q
t=q}o=new Uint16Array(d)
this.e1(t.b,b,c,d,o)
return n},
iu(a,b,c){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=new A.fb(new A.dB())
d.dV(128)
if(this.eI(d,7,a,19)===0)return!1
t=this.b
if(t.af(1)!==0){s=2+t.af(2+2*t.af(3))
if(s>b)return!1}else s=b
for(r=8,q=0;q<b;s=p){p=s-1
if(s===0)break
if(t.a>=32)t.c0()
o=d.b.a
o.toString
n=o.a
o=o.b+(t.cu()&127)
if(!(o<n.length))return A.a(n,o)
m=n[o]
t.a=t.a+m.a
l=m.b
if(l<16){k=q+1
c.$flags&2&&A.b(c)
if(!(q>=0&&q<c.length))return A.a(c,q)
c[q]=l
if(l!==0)r=l
q=k}else{j=l-16
if(!(j<3))return A.a(B.ba,j)
i=B.ba[j]
h=B.dP[j]
g=t.af(i)+h
if(q+g>b)return!1
f=l===16?r:0
for(o=c.$flags|0;e=g-1,g>0;g=e,q=k){k=q+1
o&2&&A.b(c)
if(!(q>=0&&q<c.length))return A.a(c,q)
c[q]=f}}}return!0},
ez(a,b,c){var t,s,r,q,p,o,n,m=this.b,l=m.af(1)
B.X.aB(b,0,a,0)
if(l!==0){t=m.af(1)
s=m.af(m.af(1)===0?1:8)
b.$flags&2&&A.b(b)
r=b.length
if(!(s<r))return A.a(b,s)
b[s]=1
if(t+1===2){s=m.af(8)
if(!(s<r))return A.a(b,s)
b[s]=1}q=!0}else{p=new Int32Array(19)
o=m.af(4)+4
for(n=0;n<o;++n){if(!(n<19))return A.a(B.bw,n)
t=B.bw[n]
r=m.af(3)
if(!(t<19))return A.a(p,t)
p[t]=r}q=this.iu(p,a,b)}return q&&!m.b?this.eI(c,8,b,a):0},
cJ(a,b,c){var t=c.a,s=a.a
c.a=t+s
c.b=(c.b|B.a.O(a.b,b))>>>0
return s},
h3(a){var t,s,r,q,p,o,n,m,l,k,j=this
for(t=a.a,s=t.length,r=a.f,q=r.length,p=0;p<64;++p){if(!(p<q))return A.a(r,p)
o=r[p]
if(0>=s)return A.a(t,0)
n=t[0]
m=n.a
n=n.b+p
if(!(n<m.length))return A.a(m,n)
l=m[n]
n=l.b
if(n>=256){o.a=l.a+256
o.b=n}else{o.b=o.a=0
k=B.a.a_(p,j.cJ(l,8,o))
if(1>=s)return A.a(t,1)
n=t[1]
m=n.a
n=n.b+k
if(!(n<m.length))return A.a(m,n)
k=B.a.a_(k,j.cJ(m[n],16,o))
if(2>=s)return A.a(t,2)
n=t[2]
m=n.a
n=n.b+k
if(!(n<m.length))return A.a(m,n)
k=B.a.a_(k,j.cJ(m[n],0,o))
if(3>=s)return A.a(t,3)
n=t[3]
m=n.a
n=n.b+k
if(!(n<m.length))return A.a(m,n)
B.a.a_(k,j.cJ(m[n],24,o))}}},
iw(a8,a9,b0,b1){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4=this,a5=null,a6=a8>0,a7=280+(a6?B.a.O(1,a8):0)
if(!(a8<12))return A.a(B.bj,a8)
t=B.bj[a8]
s=b1==null
if(s&&a9!==b0)return a5
r=new Int32Array(a7)
q=J.ag(a9,u.ct)
for(p=0;p<a9;++p)q[p]=A.ne()
o=new A.fb(new A.dB())
o.dV(a9*t)
a4.ay=o
for(o=!s,n=0;n<b0;++n){if(o){if(!(n<b1.length))return A.a(b1,n)
m=b1[n]===-1}else m=!1
if(m)for(l=0;l<5;++l){k=B.bl[l]
if(a4.ez(l===0&&a6?k+B.a.O(1,a8):k,r,a5)===0)return a5}else{if(s)m=n
else{if(!(n<b1.length))return A.a(b1,n)
m=b1[n]}if(!(m>=0&&m<a9))return A.a(q,m)
j=q[m]
i=j.a
for(m=i.length,h=0,g=!0,f=0,l=0;l<5;++l){k=B.bl[l]
if(l===0&&a6)k+=B.a.O(1,a8)
e=a4.ez(k,r,a4.ay)
d=a4.ay.b.b
d.toString
B.c.i(i,l,d)
if(e===0)return a5
if(g&&B.hH[l]===1){if(!(l<m))return A.a(i,l)
d=i[l]
c=d.a
d=d.b
if(!(d<c.length))return A.a(c,d)
g=c[d].a===0}if(!(l<m))return A.a(i,l)
d=i[l]
c=d.a
d=d.b
if(!(d<c.length))return A.a(c,d)
f+=c[d].a
d=a4.ay.b
d.d+=e
c=d.b
d.b=new A.dA(c.a,c.b+e)
if(l<=3){b=r[0]
for(a=1;a<k;++a){if(!(a<a7))return A.a(r,a)
a0=r[a]
if(a0>b)b=a0}h+=b}}j.b=g
j.d=!1
d=!1
if(g){if(1>=m)return A.a(i,1)
c=i[1]
a1=c.a
c=c.b
if(!(c<a1.length))return A.a(a1,c)
a2=a1[c].b
if(2>=m)return A.a(i,2)
c=i[2]
a1=c.a
c=c.b
if(!(c<a1.length))return A.a(a1,c)
a3=a1[c].b
if(3>=m)return A.a(i,3)
m=i[3]
c=m.a
m=m.b
if(!(m<c.length))return A.a(c,m)
m=(c[m].b<<24|a2<<16|a3)>>>0
j.c=m
if(f===0){d=i[0]
c=d.a
d=d.b
if(!(d<c.length))return A.a(c,d)
d=c[d].b<256}if(d){j.d=!0
c=i[0]
a1=c.a
c=c.b
if(!(c<a1.length))return A.a(a1,c)
j.c=(m|a1[c].b<<8)>>>0}m=d}else m=d
m=!m&&h<6
j.e=m
if(m)a4.h3(j)}}return q},
cS(a){var t
if(a<4)return a+1
t=B.a.j(a-2,1)
return B.a.O(2+(a&1),t)+this.b.af(t)+1},
ev(a,b){var t,s,r
if(b>120)return b-120
else{t=b-1
if(!(t>=0))return A.a(B.bm,t)
s=B.bm[t]
r=(s>>>4)*a+(8-(s&15))
return r>=1?r:1}},
hH(a,b){var t,s,r,q,p,o,n,m,l=B.a.O(1,B.a.a_(8,b.e)),k=new Uint32Array(l),j=b.d
j.toString
t=J.V(B.o.gB(j),0,null)
s=J.V(B.o.gB(k),0,null)
j=b.d
if(0>=j.length)return A.a(j,0)
j=j[0]
if(0>=l)return A.a(k,0)
k[0]=j
r=4*a
for(j=t.length,q=s.length,p=s.$flags|0,o=4;o<r;++o){if(!(o<j))return A.a(t,o)
n=t[o]
m=o-4
if(!(m<q))return A.a(s,m)
m=s[m]
p&2&&A.b(s)
if(!(o<q))return A.a(s,o)
s[o]=n+m&255}for(r=4*l;o<r;++o){p&2&&A.b(s)
if(!(o<q))return A.a(s,o)
s[o]=0}b.d=k
return!0},
cf(a,b,c,d,e){var t
if(c===0||a==null)return 0
t=b*B.a.j(e,c)+B.a.j(d,c)
if(!(t<a.length))return A.a(a,t)
return a[t]},
eg(a,b){var t=this,s=t.cf(t.as,t.Q,t.z,a,b),r=t.ax
if(!(s<r.length))return A.a(r,s)
return r[s]}}
A.ft.prototype={
jb(a,b){return this.hI(a,b)}}
A.h7.prototype={
cu(){var t,s,r,q=this.a
if(q<32){t=this.d
s=B.a.a0(t[0],q)
t=t[1]
if(!(q>=0))return A.a(B.V,q)
r=s+((t&B.V[q])>>>0)*(B.V[32-q]+1)}else{t=this.d
r=q===32?t[1]:B.a.a0(t[1],q-32)}return r},
af(a){var t,s,r=this
if(!r.b&&a<25){t=r.cu()
if(!(a<33))return A.a(B.V,a)
s=B.V[a]
r.a+=a
r.c0()
return(t&s)>>>0}else{r.b=!0
throw A.f(A.n("Not enough data in input."))}},
c0(){var t,s,r,q=this,p=q.c,o=q.d,n=o.$flags|0,m=p.c
for(;;){if(!(q.a>=8&&p.d<m))break
t=J.c(p.a,p.d++)
s=o[0]
r=o[1]
n&2&&A.b(o)
o[0]=(s>>>8)+(r&255)*16777216
o[1]=r>>>8
o[1]=(o[1]|t*16777216)>>>0
q.a-=8}}}
A.ix.prototype={}
A.co.prototype={
ad(){return"VP8LImageTransformType."+this.b}}
A.h8.prototype={
jk(a,b,c,d,e,f){var t,s,r,q,p=this,o=p.b
switch(p.a.a){case 2:p.iT(e,f,(b-a)*o)
break
case 0:p.jm(a,b,c,d,e,f)
if(b!==p.c){t=f-o
B.o.ar(e,t,t+o,c,f+(b-a-1)*o)}break
case 1:p.iW(a,b,c,d,e,f)
break
case 3:if(d===f&&p.e>0){s=b-a
r=s*A.bI(o,p.e)
q=f+s*o-r
B.o.ar(e,q,q+r,c,f)
p.eX(a,b,c,q,e,f)}else p.eX(a,b,c,d,e,f)
break}},
iV(a,b,c,d){var t,s,r,q,p,o,n=this.e,m=B.a.a_(8,n),l=this.b,k=this.d
if(m<8){t=B.a.O(1,n)-1
s=B.a.O(1,m)-1
for(r=a;r<b;++r)for(q=0,p=0;p<l;++p){if((p&t)>>>0===0){q=J.c(c.a,c.d);++c.d}n=(q&s)>>>0
if(!(n>=0&&n<k.length))return A.a(k,n)
n=k[n]
J.x(d.a,d.d,n>>>8&255);++d.d
q=B.a.j(q,m)}}else for(r=a;r<b;++r)for(p=0;p<l;++p){o=J.c(c.a,c.d);++c.d
if(!(o>=0&&o<k.length))return A.a(k,o)
n=k[o]
J.x(d.a,d.d,n>>>8&255);++d.d}},
eX(a,b,c,d,e,f){var t,s,r,q,p,o,n,m,l,k=this.e,j=B.a.a_(8,k),i=this.b,h=this.d
if(j<8){t=B.a.O(1,k)-1
s=B.a.O(1,j)-1
for(k=e.$flags|0,r=c.length,q=a;q<b;++q)for(p=0,o=0;o<i;++o,f=m){if((o&t)>>>0===0){n=d+1
if(!(d>=0&&d<r))return A.a(c,d)
p=c[d]>>>8&255
d=n}m=f+1
l=p&s
if(!(l>=0&&l<h.length))return A.a(h,l)
l=h[l]
k&2&&A.b(e)
if(!(f>=0&&f<e.length))return A.a(e,f)
e[f]=l
p=B.a.a_(p,j)}}else for(k=c.length,r=e.$flags|0,q=a;q<b;++q)for(o=0;o<i;++o,f=m,d=n){m=f+1
h.toString
n=d+1
if(!(d>=0&&d<k))return A.a(c,d)
l=c[d]>>>8&255
if(!(l<h.length))return A.a(h,l)
l=h[l]
r&2&&A.b(e)
if(!(f>=0&&f<e.length))return A.a(e,f)
e[f]=l}},
iW(a4,a5,a6,a7,a8,a9){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=this,a=b.b,a0=b.e,a1=B.a.O(1,a0)-1,a2=A.bI(a,a0),a3=B.a.j(a4,b.e)*a2
for(a0=a6.length,t=a8.$flags|0,s=a4;s<a5;){r=new Uint8Array(3)
for(q=a3,p=0;p<a;++p){if((p&a1)>>>0===0){o=b.d
n=q+1
if(!(q<o.length))return A.a(o,q)
o=o[q]
r[0]=o&255
r[1]=o>>>8&255
r[2]=o>>>16&255
q=n}o=a9+p
m=a7+p
if(!(m<a0))return A.a(a6,m)
m=a6[m]
l=m>>>8&255
k=r[0]
j=$.an()
j.$flags&2&&A.b(j)
j[0]=k
k=$.av()
if(0>=k.length)return A.a(k,0)
i=k[0]
j[0]=l
h=k[0]
g=$.hq()
g.$flags&2&&A.b(g)
g[0]=i*h
f=$.jK()
if(0>=f.length)return A.a(f,0)
e=(m>>>16&255)+(f[0]>>>5)>>>0&255
j[0]=r[1]
i=k[0]
j[0]=l
g[0]=i*k[0]
d=f[0]
j[0]=r[2]
i=k[0]
j[0]=e
g[0]=i*k[0]
c=f[0]
t&2&&A.b(a8)
if(!(o<a8.length))return A.a(a8,o)
a8[o]=(m&4278255360|e<<16|((m&255)+(d>>>5)>>>0)+(c>>>5)>>>0&255)>>>0}a9+=a
a7+=a;++s
if((s&a1)>>>0===0)a3+=a2}},
c5(a,b){return(((a&4278255360)>>>0)+((b&4278255360)>>>0)&4278255360|(a&16711935)+(b&16711935)&16711935)>>>0},
jm(b0,b1,b2,b3,b4,b5){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7=this,a8=4278190080,a9=a7.b
if(b0===0){t=b2.length
if(!(b3<t))return A.a(b2,b3)
s=a7.c5(b2[b3],a8)
b4.$flags&2&&A.b(b4)
r=b4.length
if(!(b5<r))return A.a(b4,b5)
b4[b5]=s
q=b3+1
p=b5+1
o=a9-1
n=b4[b5]
for(s=b4.$flags|0,m=0;m<o;++m){l=q+m
if(!(l<t))return A.a(b2,l)
n=a7.c5(b2[l],n)
l=p+m
s&2&&A.b(b4)
if(!(l<r))return A.a(b4,l)
b4[l]=n}b3+=a9
b5+=a9;++b0}t=a7.e
k=B.a.O(1,t)
j=k-1
i=A.bI(a9,t)
h=B.a.j(b0,a7.e)*i
for(t=b2.length,s=~j,r=b4.length,g=b0;g<b1;){l=b5-a9
if(!(l>=0&&l<r))return A.a(b4,l)
f=b4[l]
if(!(b3<t))return A.a(b2,b3)
l=a7.c5(b2[b3],f)
b4.$flags&2&&A.b(b4)
if(!(b5<r))return A.a(b4,b5)
b4[b5]=l
for(e=h,d=1;d<a9;d=a0,e=c){l=a7.d
c=e+1
if(!(e<l.length))return A.a(l,e)
b=l[e]>>>8&15
a=$.or[b]
a0=((d&s)>>>0)+k
if(a0>a9)a0=a9
a1=b3+d
l=b5+d
a2=l-a9
a3=a0-d
if(b===0)for(a4=b4.$flags|0,m=0;m<a3;++m){a5=l+m
a6=a1+m
if(!(a6>=0&&a6<t))return A.a(b2,a6)
a6=a7.c5(b2[a6],a8)
a4&2&&A.b(b4)
if(!(a5>=0&&a5<r))return A.a(b4,a5)
b4[a5]=a6}else if(b===1){a4=l-1
if(!(a4>=0&&a4<r))return A.a(b4,a4)
n=b4[a4]
for(a4=b4.$flags|0,m=0;m<a3;++m){a5=a1+m
if(!(a5>=0&&a5<t))return A.a(b2,a5)
n=a7.c5(b2[a5],n)
a5=l+m
a4&2&&A.b(b4)
if(!(a5>=0&&a5<r))return A.a(b4,a5)
b4[a5]=n}}else for(m=0;m<a3;++m){a4=l+m
a5=a4-1
if(!(a5>=0&&a5<r))return A.a(b4,a5)
f=a.$3(b4[a5],b4,a2+m)
a5=a1+m
if(!(a5>=0&&a5<t))return A.a(b2,a5)
a5=a7.c5(b2[a5],f)
b4.$flags&2&&A.b(b4)
if(!(a4>=0&&a4<r))return A.a(b4,a4)
b4[a4]=a5}}b3+=a9
b5+=a9;++g
if((g&j)>>>0===0)h+=i}},
iT(a,b,c){var t,s,r,q,p,o
for(t=a.length,s=a.$flags|0,r=0;r<c;++r){q=b+r
if(!(q<t))return A.a(a,q)
p=a[q]
o=p>>>8&255
s&2&&A.b(a)
a[q]=(p&4278255360|(p&16711935)+(o<<16|o)&16711935)>>>0}}}
A.iD.prototype={
gf5(){var t=this,s=t.d
if(s>1||t.e>=4||t.f>1||t.r!==0)return!1
return!0},
j_(a,b,c){var t,s,r,q,p,o,n=this
if(!n.gf5())return!1
t=n.e
if(!(t<4))return A.a(B.bP,t)
s=B.bP[t]
if(n.d===0){t=n.b
r=a*t
q=n.a
B.e.ar(c,r,r+b*t,q.a,q.d-q.b+r)}else{t=a+b
q=n.x
q===$&&A.d()
q.dx=c
p=q.c
if(n.y)t=q.hg(p.a,p.b,t)
else{o=q.cx
o.toString
q=q.dg(o,p.a,p.b,t,u.d6.a(q.gja()))
t=q}if(!t)return!1}if(s!=null){t=n.b
s.$6(t,n.c,t,a,b,c)}if(n.f===1)if(!n.hB(c,n.b,n.c,a,b))return!1
if(a+b>=n.c)n.w=!0
return!0},
hB(a,b,c,d,e){if(b<=0||c<=0||d<0||e<0||d+e>c)return!1
return!0}}
A.ez.prototype={
fX(a,b){var t=this,s=a.G()
t.w=0
t.f=(s&1)!==0
t.r=(s&2)===0
t.x=a.d-a.b
t.y=b-16}}
A.fu.prototype={}
A.f8.prototype={}
A.f9.prototype={}
A.dA.prototype={
gt(a){return this.a.length-this.b}}
A.dz.prototype={
c4(a,b){var t,s,r,q,p,o=b.cu()&255,n=this.a
if(!(a<n.length))return A.a(n,a)
t=n[a]
s=t.a
r=t.b+o
if(!(r<s.length))return A.a(s,r)
q=s[r].a-8
if(q>0){b.a+=8
p=b.cu()
n=n[a]
t=n.a
s=n.b+o
if(!(s<t.length))return A.a(t,s)
o=o+t[s].b+((p&B.a.W(1,q)-1)>>>0)}else n=t
t=b.a
s=n.a
n=n.b+o
if(!(n>=0&&n<s.length))return A.a(s,n)
n=s[n]
b.a=t+n.a
return n.b}}
A.dB.prototype={}
A.fb.prototype={
dV(a){var t=this.b=this.a,s=A.jT(a)
t.e=a
t.b=t.a=s}}
A.df.prototype={
ad(){return"WebPFormat."+this.b}}
A.dg.prototype={$iJ:1}
A.dK.prototype={}
A.iE.prototype={
bm(a){var t=A.v(u.L.a(a),!1,null,0)
this.b=t
if(!this.ef(t))return!1
return!0},
aP(a){var t,s=this,r=null,q=A.v(u.L.a(a),!1,r,0)
s.b=q
if(!s.ef(q))return r
q=new A.dK(B.a1,A.j([],u.J))
s.a=q
t=s.b
t.toString
if(!s.eJ(t,q))return r
q=s.a
switch(q.f.a){case 3:q.as=q.z.length
return q
case 2:t=s.b
t.toString
t.d=q.ay
if(!A.kq(t,q).cn())return r
q=s.a
q.as=q.z.length
return q
case 1:t=s.b
t.toString
t.d=q.ay
if(!A.ko(t,q).cn())return r
q=s.a
q.as=q.z.length
return q
case 0:throw A.f(A.n("Unknown format for WebP"))}},
al(a){var t,s,r,q=this,p=q.b
if(p==null||q.a==null)return null
t=q.a
if(t.e){t=t.z
s=t.length
if(a>=s)return null
if(!(a<s))return A.a(t,a)
r=t[a]
t=r.y
t===$&&A.d()
s=r.x
s===$&&A.d()
return q.e7(p.bU(t,s),a)}s=t.f
if(s===B.al)return A.kq(p.bU(t.ch,t.ay),t).bF()
else if(s===B.aK)return A.ko(p.bU(t.ch,t.ay),t).bF()
return null},
aS(a2,a3){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=this,a1=null
if(a0.aP(u.L.a(a2))==null)return a1
t=a0.a.e
if(!t)return a0.al(0)
for(t=u.N,s=u.P,r=a1,q=r,p=q,o=0;n=a0.a,o<n.as;++o){n=n.z
if(!(o<n.length))return A.a(n,o)
a3=n[o]
m=a0.al(o)
if(m==null)continue
n=a3.e
m.y=n
if(p==null||q==null){l=a0.a
k=l.a
l=l.b
j=m.gc2()
i=m.a
i=i==null?a1:i.gK()
if(i==null)i=B.f
h=m.y
g=a0.a
f=g.y
e=g.c
g=g.w
if(g.length===0)g=a1
else{g=new A.aJ(g)
d=g.gt(0)
c=g.gt(0)
b=new A.bw(A.D(t,s))
b.bS(new A.aa(g,0,Math.min(d,c),0,!1))
g=b}a=a0.a.r
p=A.R(e,g,i,h,B.j,l,a==null?a1:new A.bf("",B.P,a),f,j,a1,B.f,k,!1)
q=p}else{q=A.bz(q,!1,!1)
if(r!=null){l=r.f
l===$&&A.d()}else l=!1
if(l){l=r.a
k=r.b
j=r.c
i=r.d
A.mh(q,!1,$.mC(),l,l+j-1,k,k+i-1)}}q.y=n
n=a3.r
n===$&&A.d()
n=n?B.am:B.a2
A.kA(q,m,n,a1,a1,a3.a,a3.b,a1,a1,a1,a1)
if(q!==p)p.aZ(q)
r=a3}return p},
e7(a,b){var t,s,r,q=null,p=A.j([],u.J),o=new A.dK(B.a1,p)
if(!this.eJ(a,o))return q
t=o.f
if(t===B.a1)return q
o.as=this.a.as
if(o.e){t=p.length
if(b>=t)return q
s=p[b]
p=s.y
p===$&&A.d()
t=s.x
t===$&&A.d()
return this.e7(a.bU(p,t),b)}else{r=a.bU(o.ch,o.ay)
if(t===B.al)return A.kq(r,o).bF()
else if(t===B.aK)return A.ko(r,o).bF()}return q},
ef(a){if(a.ah(4)!=="RIFF")return!1
a.l()
if(a.ah(4)!=="WEBP")return!1
return!0},
eJ(a,b){var t,s,r,q,p,o,n,m,l,k,j,i,h
for(t=a.c,s=a.b;a.d<t;){r=a.ah(4)
q=a.l()
p=q+1>>>1<<1>>>0
o=a.d
n=o-s
switch(r){case"VP8X":if(!this.hR(a,b))return!1
break
case"VP8 ":b.ay=n
b.ch=q
b.f=B.aK
break
case"VP8L":b.ay=n
b.ch=q
b.f=B.al
break
case"ALPH":b.toString
o=a.a
m=a.e
l=J.S(o)
k=l.gt(o)
l=l.gt(o)
o=new A.aa(o,0,Math.min(k,l),0,m)
b.at=o
o.d=a.d
a.d+=p
break
case"ANIM":b.f=B.kQ
j=a.l()
o=new Uint8Array(4)
o[0]=j>>>16&255
o[1]=j>>>8&255
o[2]=j&255
o[3]=j>>>24&255
b.c=new A.bT(o)
b.y=a.m()
break
case"ANMF":if(!this.hO(a,b,q))return!1
break
case"ICCP":b.toString
i=a.ai(q)
a.d=o+(i.c-i.d)
b.r=i.a2()
break
case"EXIF":b.toString
b.w=a.ah(q)
break
case"XMP ":b.toString
a.ah(q)
break
default:a.d=o+p
break}o=a.d
h=p-(o-s-n)
if(h>0)a.d=o+h}if(!b.d)b.d=b.at!=null
return b.f!==B.a1},
hR(a,b){var t,s,r,q,p=a.G()
if((p&192)!==0)return!1
t=B.a.j(p,4)
s=B.a.j(p,1)
if((p&1)!==0)return!1
if(a.bf()!==0)return!1
r=a.bf()
q=a.bf()
b.a=r+1
b.b=q+1
b.e=(s&1)!==0
b.d=(t&1)!==0
return!0},
hO(a,b,c){var t=new A.fu(a.bf()*2,a.bf()*2,a.bf()+1,a.bf()+1,a.bf())
t.fX(a,c)
if(t.w!==0)return!1
B.c.A(b.z,t)
return!0}}
A.fc.prototype={
ad(){return"IccProfileCompression."+this.b}}
A.bf.prototype={
j7(){var t,s=this
if(s.b===B.P)return s.c
t=B.B.bP(s.c)
s.c=t
s.b=B.P
return t}}
A.f6.prototype={
ad(){return"FrameType."+this.b}}
A.bh.prototype={
gaA(){var t=this.x
return t===$?this.x=A.j([],u.g):t},
fR(a,b,c,d){var t,s,r,q=this,p=a.gK(),o=a.gc2(),n=a.a
q.e5(d,b,p,o,n==null?null:n.gR())
p=a.b
if(p!=null)q.b=A.b3(p,u.N,u.v)
p=a.d
if(p!=null){o=u.N
q.d=A.b3(p,o,o)}B.c.A(q.gaA(),q)
if(!c){t=a.gaA().length
for(p=u.g,s=1;s<t;++s){r=a.x
if(r===$)r=a.x=A.j([],p)
if(!(s<r.length))return A.a(r,s)
q.aZ(A.fg(r[s],b,!1,d))}}},
fQ(a,b,c){var t,s,r,q,p=this,o=a.b
if(o!=null)p.b=A.b3(o,u.N,u.v)
o=a.d
if(o!=null){t=u.N
p.d=A.b3(o,t,t)}B.c.A(p.gaA(),p)
if(!b&&a.gaA().length>1){s=a.gaA().length
for(o=u.g,r=1;r<s;++r){q=a.x
if(q===$)q=a.x=A.j([],o)
if(!(r<q.length))return A.a(q,r)
p.aZ(A.bz(q[r],!1,!1))}}},
aZ(a){var t=this
if(a==null)a=A.bz(t,!0,!0)
a.z=t.gaA().length
if(t.gaA().length===0||B.c.gf7(t.gaA())!==a)B.c.A(t.gaA(),a)
return a},
d0(){return this.aZ(null)},
e5(a,b,c,d,e){var t,s,r=this,q=null
switch(c.a){case 0:if(e==null){t=B.b.b0(a*d/8)
s=new A.cT($,t,q,a,b,d)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}else{t=B.b.b0(a/8)
s=new A.cT($,t,e,a,b,1)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}break
case 1:if(e==null){t=B.b.b0(a*(d<<1>>>0)/8)
s=new A.cV($,t,q,a,b,d)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}else{t=B.b.b0(a/4)
s=new A.cV($,t,e,a,b,1)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}break
case 2:if(e==null){if(d===2)t=a
else if(d===4)t=a*2
else t=d===3?B.b.b0(a*1.5):B.b.b0(a/2)
s=new A.cX($,t,q,a,b,d)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}else{t=B.b.b0(a/2)
s=new A.cX($,t,e,a,b,1)
t=Math.max(t*b,1)
s.d=new Uint8Array(t)
r.a=s}break
case 3:if(e==null)r.a=A.lg(a,b,d)
else r.a=new A.cY(new Uint8Array(a*b),e,a,b,1)
break
case 4:t=a*b
if(e==null)r.a=new A.cU(new Uint16Array(t*d),q,a,b,d)
else r.a=new A.cU(new Uint16Array(t),e,a,b,1)
break
case 5:r.a=A.nh(a,b,d)
break
case 6:r.a=new A.dG(new Int8Array(a*b*d),a,b,d)
break
case 7:r.a=new A.dE(new Int16Array(a*b*d),a,b,d)
break
case 8:r.a=new A.dF(new Int32Array(a*b*d),a,b,d)
break
case 9:r.a=A.nf(a,b,d)
break
case 10:r.a=A.ng(a,b,d)
break
case 11:r.a=new A.dD(new Float64Array(a*b*4*d),a,b,d)
break}},
D(a){var t=this
return"Image("+t.ga5()+", "+t.gV()+", "+t.gK().b+", "+t.gc2()+")"},
ga5(){var t=this.a
t=t==null?null:t.a
return t==null?0:t},
gV(){var t=this.a
t=t==null?null:t.b
return t==null?0:t},
gK(){var t=this.a
t=t==null?null:t.gK()
return t==null?B.f:t},
gbG(){var t=this.e
return t==null?this.e=new A.bw(A.D(u.N,u.P)):t},
fq(a,b){var t=this,s=t.b;(s==null?t.b=A.D(u.N,u.v):s).i(0,a,b)
if(t.b.a===0)t.b=null},
gI(a){var t=this.a
return t.gI(t)},
gB(a){var t=this.a
t=t==null?null:t.gB(t)
if(t==null)t=B.e.gB(new Uint8Array(0))
return t},
gc2(){var t=this.a
t=t==null?null:t.gR()
t=t==null?null:t.b
if(t==null){t=this.a
t=t==null?null:t.c}return t==null?0:t},
gcp(){var t=this.a
return(t==null?null:t.gR())!=null},
f4(a,b){return a>=0&&b>=0&&a<this.ga5()&&b<this.gV()},
aI(a,b,c,d){var t=this.a
t=t==null?null:t.aI(a,b,c,d)
if(t==null)t=new A.aS(new Uint8Array(0))
return t},
L(a,b,c){var t=this.a
t=t==null?null:t.L(a,b,c)
return t==null?new A.G():t},
aJ(a,b){return this.L(a,b,null)},
ab(a,b){if(a<0||a>=this.ga5()||b<0||b>=this.gV())return new A.G()
return this.L(a,b,null)},
dN(a,b,c){switch(c.a){case 0:return this.ab(B.b.h(a),B.b.h(b))
case 1:case 3:return this.fn(a,b)
case 2:return this.fm(a,b)}},
fn(a,b){var t,s,r,q,p,o,n=this,m=B.b.h(a),l=m-(a>=0?0:1),k=l+1
m=B.b.h(b)
t=m-(b>=0?0:1)
s=t+1
m=new A.hO(a-l,b-t)
r=n.ab(l,t)
q=s>=n.gV()?r:n.ab(l,s)
p=k>=n.ga5()?r:n.ab(k,t)
o=k>=n.ga5()||s>=n.gV()?r:n.ab(k,s)
return n.aI(m.$4(r.gn(),p.gn(),q.gn(),o.gn()),m.$4(r.gp(),p.gp(),q.gp(),o.gp()),m.$4(r.gq(),p.gq(),q.gq(),o.gq()),m.$4(r.gu(),p.gu(),q.gu(),o.gu()))},
fm(d1,d2){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,c0,c1,c2,c3,c4,c5=this,c6=B.b.h(d1),c7=c6-(d1>=0?0:1),c8=c7-1,c9=c7+1,d0=c7+2
c6=B.b.h(d2)
t=c6-(d2>=0?0:1)
s=t-1
r=t+1
q=t+2
p=d1-c7
o=d2-t
c6=new A.hN()
n=c5.ab(c7,t)
m=c8<0
l=!m
k=!l||s<0?n:c5.ab(c8,s)
j=m?n:c5.ab(c7,s)
i=s<0
h=i||c9>=c5.ga5()?n:c5.ab(c9,s)
g=d0>=c5.ga5()||i?n:c5.ab(d0,s)
f=c6.$5(p,k.gn(),j.gn(),h.gn(),g.gn())
e=c6.$5(p,k.gp(),j.gp(),h.gp(),g.gp())
d=c6.$5(p,k.gq(),j.gq(),h.gq(),g.gq())
c=c6.$5(p,k.gu(),j.gu(),h.gu(),g.gu())
b=m?n:c5.ab(c8,t)
a=c9>=c5.ga5()?n:c5.ab(c9,t)
a0=d0>=c5.ga5()?n:c5.ab(d0,t)
a1=c6.$5(p,b.gn(),n.gn(),a.gn(),a0.gn())
a2=c6.$5(p,b.gp(),n.gp(),a.gp(),a0.gp())
a3=c6.$5(p,b.gq(),n.gq(),a.gq(),a0.gq())
a4=c6.$5(p,b.gu(),n.gu(),a.gu(),a0.gu())
a5=!l||r>=c5.gV()?n:c5.ab(c8,r)
a6=r>=c5.gV()?n:c5.ab(c7,r)
a7=c9>=c5.ga5()||r>=c5.gV()?n:c5.ab(c9,r)
a8=d0>=c5.ga5()||r>=c5.gV()?n:c5.ab(d0,r)
a9=c6.$5(p,a5.gn(),a6.gn(),a7.gn(),a8.gn())
b0=c6.$5(p,a5.gp(),a6.gp(),a7.gp(),a8.gp())
b1=c6.$5(p,a5.gq(),a6.gq(),a7.gq(),a8.gq())
b2=c6.$5(p,a5.gu(),a6.gu(),a7.gu(),a8.gu())
b3=!l||q>=c5.gV()?n:c5.ab(c8,q)
b4=q>=c5.gV()?n:c5.ab(c7,q)
b5=c9>=c5.ga5()||q>=c5.gV()?n:c5.ab(c9,q)
b6=d0>=c5.ga5()||q>=c5.gV()?n:c5.ab(d0,q)
b7=c6.$5(p,b3.gn(),b4.gn(),b5.gn(),b6.gn())
b8=c6.$5(p,b3.gp(),b4.gp(),b5.gp(),b6.gp())
b9=c6.$5(p,b3.gq(),b4.gq(),b5.gq(),b6.gq())
c0=c6.$5(p,b3.gu(),b4.gu(),b5.gu(),b6.gu())
c1=c6.$5(o,f,a1,a9,b7)
c2=c6.$5(o,e,a2,b0,b8)
c3=c6.$5(o,d,a3,b1,b9)
c4=c6.$5(o,c,a4,b2,c0)
return c5.aI(B.b.h(c1),B.b.h(c2),B.b.h(c3),B.b.h(c4))},
bI(a,b,c){var t
if(u.dv.b(c))if(c.gb2().gR()!=null)if(this.gcp()){t=this.a
if(t!=null)t.a3(a,b,c.gN(),0,0)
return}t=this.a
if(t!=null)t.ak(a,b,c.gn(),c.gp(),c.gq(),c.gu())},
a3(a,b,c,d,e){var t=this.a
return t==null?null:t.a3(a,b,c,d,e)},
gE(){var t=this.a
t=t==null?null:t.gE()
return t==null?0:t},
aK(a,b){var t=this.a
return t==null?null:t.aK(0,b)},
dE(a){return this.aK(0,null)},
iY(a7,a8){var t,s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5=this,a6=null
if(a7==null)a7=a5.gK()
if(a8==null)a8=a5.gc2()
t=B.bT.k(0,a7)
s=!1
if(a7===a5.gK())if(a8===a5.gc2()){r=a5.a
s=(r==null?a6:r.gR())==null}if(s){q=A.bz(a5,!1,!1)
return q}for(s=a5.gaA(),r=s.length,p=u.N,o=u.p,n=a6,m=0;m<s.length;s.length===r||(0,A.a_)(s),++m,n=d){l=s[m]
k=l.a
j=k==null
i=j?a6:k.a
if(i==null)i=0
k=j?a6:k.b
if(k==null)k=0
j=l.e
j=j==null?a6:A.ds(j)
h=l.c
if(h==null)h=a6
else{g=h.a
f=h.b
h=h.c
h=new A.bf(g,f,new Uint8Array(h.subarray(0,A.b6(0,a6,h.length))))}g=l.f
g=g==null?a6:new A.aS(new Uint8Array(A.w(g.a)))
f=l.w
e=l.r
q=A.R(g,j,a7,l.y,f,k,h,e,a8,a6,B.f,i,!1)
k=l.d
q.sjy(k!=null?A.b3(k,p,p):a6)
if(n!=null){n.aZ(q)
d=n}else d=q
k=q.a
c=k==null?a6:k.gR()
k=q.a
k=k==null?a6:k.gR()
b=k==null?a6:k.gK()
if(b==null)b=a7
k=l.a
if(c!=null){a=A.D(o,o)
a0=k==null?a6:k.L(0,0,a6)
if(a0==null)a0=new A.G()
for(k=q.a,k=k.gI(k),a1=a6,a2=0;k.F();){a3=k.gM()
a4=A.mm(B.b.bQ(a0.gaa()*255),B.b.bQ(a0.ga6()*255),B.b.bQ(a0.ga9()*255),0)
if(a.ae(a4)){j=a.k(0,a4)
j.toString
a3.sN(j)}else{a.i(0,a4,a2)
a3.sN(a2)
a1=A.az(a0,t,b,a8,a1)
c.b5(a2,a1.gn(),a1.gp(),a1.gq());++a2}a0.F()}}else{a0=k==null?a6:k.L(0,0,a6)
if(a0==null)a0=new A.G()
for(k=q.a,k=k.gI(k);k.F();){A.az(a0,t,a6,a6,k.gM())
a0.F()}}}n.toString
return n},
eY(a){return this.iY(null,a)},
iU(a){var t,s,r,q
u.ck.a(a)
if(this.d==null){t=u.N
this.d=A.D(t,t)}for(t=new A.O(a,a.r,a.e,A.l(a).v("O<1>"));t.F();){s=t.d
r=this.d
r.toString
q=a.k(0,s)
q.toString
r.i(0,s,q)}},
ha(a,b,c){var t,s=65536
switch(b.a){case 0:return null
case 1:return null
case 2:return null
case 3:t=a===B.l?s:256
return new A.aW(new Uint8Array(t*c),t,c)
case 4:t=a===B.l?s:256
return new A.eb(new Uint16Array(t*c),t,c)
case 5:t=a===B.l?s:256
return new A.ec(new Uint32Array(t*c),t,c)
case 6:t=a===B.l?s:256
return new A.ea(new Int8Array(t*c),t,c)
case 7:t=a===B.l?s:256
return new A.e8(new Int16Array(t*c),t,c)
case 8:t=a===B.l?s:256
return new A.e9(new Int32Array(t*c),t,c)
case 9:t=a===B.l?s:256
return new A.e5(new Uint16Array(t*c),t,c)
case 10:t=a===B.l?s:256
return new A.e6(new Float32Array(t*c),t,c)
case 11:t=a===B.l?s:256
return new A.e7(new Float64Array(t*c),t,c)}},
sjy(a){this.d=u.cZ.a(a)}}
A.hO.prototype={
$4(a,b,c,d){var t=this.b
return a+this.a*(b-a+t*(a+d-c-b))+t*(c-a)},
$S:31}
A.hN.prototype={
$5(a,b,c,d,e){var t=-b,s=a*a
return c+0.5*(a*(t+d)+s*(2*b-5*c+4*d-e)+s*a*(t+3*c-3*d+e))},
$S:32}
A.af.prototype={
gR(){return null}}
A.cR.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Uint16Array(s.length)
else s=new Uint16Array(A.w(s))
return new A.cR(s,t.a,t.b,t.c)},
gK(){return B.C},
gB(a){return B.Y.gB(this.d)},
gI(a){return A.k5(this)},
b4(a,b,c,d,e){return A.aX(A.k5(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){return 1},
aI(a,b,c,d){var t=new Uint16Array(4),s=new A.cz(t)
t[0]=A.I(a)
t[1]=A.I(b)
t[2]=A.I(c)
t[3]=A.I(d)
t=s
return t},
L(a,b,c){if(c==null||!(c instanceof A.c9)||c.d!==this)c=A.k5(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*this.a*s+a*s
s=this.d
t=A.I(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=A.I(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=A.I(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=A.I(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=A.I(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=A.I(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=A.I(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=A.I(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataFloat16("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.cS.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Float32Array(s.length)
else s=new Float32Array(A.w(s))
return new A.cS(s,t.a,t.b,t.c)},
gK(){return B.H},
gB(a){return B.ai.gB(this.d)},
gI(a){return A.k6(this)},
b4(a,b,c,d,e){return A.aX(A.k6(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){return 1},
aI(a,b,c,d){var t=new Float32Array(4),s=new A.cA(t)
t[0]=a
t[1]=b
t[2]=c
t[3]=d
t=s
return t},
L(a,b,c){if(c==null||!(c instanceof A.ca)||c.d!==this)c=A.k6(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t=this.c,s=b*this.a*t+a*t
t=this.d
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=c},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=c
if(r>1){s=q+1
if(!(s<t))return A.a(p,s)
p[s]=d
if(r>2){r=q+2
if(!(r<t))return A.a(p,r)
p[r]=e}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=c
if(r>1){s=q+1
if(!(s<t))return A.a(p,s)
p[s]=d
if(r>2){s=q+2
if(!(s<t))return A.a(p,s)
p[s]=e
if(r>3){r=q+3
if(!(r<t))return A.a(p,r)
p[r]=f}}}},
D(a){return"ImageDataFloat32("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.dD.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Float64Array(s.length)
else s=new Float64Array(A.w(s))
return new A.dD(s,t.a,t.b,t.c)},
gK(){return B.L},
gB(a){return B.aj.gB(this.d)},
gt(a){return this.d.byteLength},
gI(a){return A.k7(this)},
b4(a,b,c,d,e){return A.aX(A.k7(this),b,c,d,e)},
gE(){return 1},
aI(a,b,c,d){var t=new Float64Array(4),s=new A.cB(t)
t[0]=a
t[1]=b
t[2]=c
t[3]=d
t=s
return t},
L(a,b,c){if(c==null||!(c instanceof A.cb)||c.d!==this)c=A.k7(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t=this.c,s=b*this.a*t+a*t
t=this.d
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=c},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=c
if(r>1){s=q+1
if(!(s<t))return A.a(p,s)
p[s]=d
if(r>2){r=q+2
if(!(r<t))return A.a(p,r)
p[r]=e}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=c
if(r>1){s=q+1
if(!(s<t))return A.a(p,s)
p[s]=d
if(r>2){s=q+2
if(!(s<t))return A.a(p,s)
p[s]=e
if(r>3){r=q+3
if(!(r<t))return A.a(p,r)
p[r]=f}}}},
D(a){return"ImageDataFloat64("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.dE.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Int16Array(s.length)
else s=new Int16Array(A.w(s))
return new A.dE(s,t.a,t.b,t.c)},
gK(){return B.N},
gB(a){return B.aA.gB(this.d)},
gI(a){return A.k8(this)},
b4(a,b,c,d,e){return A.aX(A.k8(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){return 32767},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new Int16Array(4),o=new A.cC(p)
p[0]=t
p[1]=s
p[2]=r
p[3]=q
t=o
return t},
L(a,b,c){if(c==null||!(c instanceof A.cc)||c.d!==this)c=A.k8(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*this.a*s+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataInt16("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.dF.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Int32Array(s.length)
else s=new Int32Array(A.w(s))
return new A.dF(s,t.a,t.b,t.c)},
gK(){return B.O},
gB(a){return B.X.gB(this.d)},
gI(a){return A.k9(this)},
b4(a,b,c,d,e){return A.aX(A.k9(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){return 2147483647},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new Int32Array(4),o=new A.cD(p)
p[0]=t
p[1]=s
p[2]=r
p[3]=q
t=o
return t},
L(a,b,c){if(c==null||!(c instanceof A.cd)||c.d!==this)c=A.k9(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*this.a*s+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataInt32("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.dG.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Int8Array(s.length)
else s=new Int8Array(A.w(s))
return new A.dG(s,t.a,t.b,t.c)},
gK(){return B.M},
gB(a){return B.aB.gB(this.d)},
gI(a){return A.ka(this)},
b4(a,b,c,d,e){return A.aX(A.ka(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){return 127},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new Int8Array(4),o=new A.cE(p)
p[0]=t
p[1]=s
p[2]=r
p[3]=q
t=o
return t},
L(a,b,c){if(c==null||!(c instanceof A.ce)||c.d!==this)c=A.ka(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*(this.a*s)+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*(this.a*r)+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*(this.a*r)+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataInt8("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.cT.prototype={
jL(a,b,c){var t=Math.max(this.e*b,1)
t=new Uint8Array(t)
this.d!==$&&A.kG()
this.d=t},
bb(a){var t,s=this,r=s.d
if(a){r===$&&A.d()
r=new Uint8Array(r.length)}else{r===$&&A.d()
r=new Uint8Array(A.w(r))}t=s.f
t=t==null?null:t.P()
return new A.cT(r,s.e,t,s.a,s.b,s.c)},
gK(){return B.w},
gt(a){var t=this.d
t===$&&A.d()
return t.byteLength},
gE(){var t=this.f
t=t==null?null:t.gE()
return t==null?1:t},
gB(a){var t=this.d
t===$&&A.d()
return B.e.gB(t)},
gI(a){return A.ed(this)},
b4(a,b,c,d,e){return A.aX(A.ed(this),b,c,d,e)},
aI(a,b,c,d){var t=new A.cF(4,0)
t.a8(B.b.h(a),B.b.h(b),B.b.h(c),B.b.h(d))
return t},
L(a,b,c){if(c==null||!(c instanceof A.cf)||c.f!==this)c=A.ed(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ed(s):t).Z(a,b)
s.r.an(0,c)},
a3(a,b,c,d,e){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ed(s):t).Z(a,b)
s.r.am(c,d,e)},
ak(a,b,c,d,e,f){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ed(s):t).Z(a,b)
s.r.a8(c,d,e,f)},
D(a){return"ImageDataUint1("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){},
gR(){return this.f}}
A.cU.prototype={
bb(a){var t,s=this,r=s.d
if(a)r=new Uint16Array(r.length)
else r=new Uint16Array(A.w(r))
t=s.e
t=t==null?null:t.P()
return new A.cU(r,t,s.a,s.b,s.c)},
gK(){return B.l},
gB(a){return B.Y.gB(this.d)},
gE(){var t=this.e
t=t==null?null:t.gE()
return t==null?65535:t},
gI(a){return A.kb(this)},
b4(a,b,c,d,e){return A.aX(A.kb(this),b,c,d,e)},
gt(a){return this.d.byteLength},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new Uint16Array(4),o=new A.cG(p)
p[0]=t
p[1]=s
p[2]=r
p[3]=q
t=o
return t},
L(a,b,c){if(c==null||!(c instanceof A.cg)||c.d!==this)c=A.kb(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*this.a*s+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataUint16("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){},
gR(){return this.e}}
A.cV.prototype={
jM(a,b,c){var t=Math.max(this.e*b,1)
t=new Uint8Array(t)
this.d!==$&&A.kG()
this.d=t},
bb(a){var t,s=this,r=s.d
if(a){r===$&&A.d()
r=new Uint8Array(r.length)}else{r===$&&A.d()
r=new Uint8Array(A.w(r))}t=s.f
t=t==null?null:t.P()
return new A.cV(r,s.e,t,s.a,s.b,s.c)},
gK(){return B.y},
gB(a){var t=this.d
t===$&&A.d()
return B.e.gB(t)},
gI(a){return A.ee(this)},
b4(a,b,c,d,e){return A.aX(A.ee(this),b,c,d,e)},
gt(a){var t=this.d
t===$&&A.d()
return t.byteLength},
gE(){var t=this.f
t=t==null?null:t.gE()
return t==null?3:t},
aI(a,b,c,d){var t=new A.cH(4,0)
t.a8(B.b.h(a),B.b.h(b),B.b.h(c),B.b.h(d))
return t},
L(a,b,c){if(c==null||!(c instanceof A.ch)||c.f!==this)c=A.ee(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ee(s):t).Z(a,b)
s.r.ao(0,c)},
a3(a,b,c,d,e){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ee(s):t).Z(a,b)
s.r.am(c,d,e)},
ak(a,b,c,d,e,f){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ee(s):t).Z(a,b)
s.r.a8(c,d,e,f)},
D(a){return"ImageDataUint2("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){},
gR(){return this.f}}
A.cW.prototype={
bb(a){var t=this,s=t.d
if(a)s=new Uint32Array(s.length)
else s=new Uint32Array(A.w(s))
return new A.cW(s,t.a,t.b,t.c)},
gK(){return B.I},
gB(a){return B.o.gB(this.d)},
gE(){return 4294967295},
gI(a){return A.kc(this)},
b4(a,b,c,d,e){return A.aX(A.kc(this),b,c,d,e)},
gt(a){return this.d.byteLength},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new Uint32Array(4),o=new A.cI(p)
p[0]=t
p[1]=s
p[2]=r
p[3]=q
t=o
return t},
L(a,b,c){if(c==null||!(c instanceof A.ci)||c.d!==this)c=A.kc(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*this.a*s+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*this.a*r+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataUint32("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){}}
A.cX.prototype={
jN(a,b,c){var t=Math.max(this.e*b,1)
t=new Uint8Array(t)
this.d!==$&&A.kG()
this.d=t},
bb(a){var t,s=this,r=s.d
if(a){r===$&&A.d()
r=new Uint8Array(r.length)}else{r===$&&A.d()
r=new Uint8Array(A.w(r))}t=s.f
t=t==null?null:t.P()
return new A.cX(r,s.e,t,s.a,s.b,s.c)},
gK(){return B.z},
gB(a){var t=this.d
t===$&&A.d()
return B.e.gB(t)},
gI(a){return A.ef(this)},
b4(a,b,c,d,e){return A.aX(A.ef(this),b,c,d,e)},
gt(a){var t=this.d
t===$&&A.d()
return t.byteLength},
gE(){var t=this.f
t=t==null?null:t.gE()
return t==null?15:t},
aI(a,b,c,d){var t=B.b.h(a),s=B.b.h(b),r=B.b.h(c),q=B.b.h(d),p=new A.cJ(4,new Uint8Array(2))
p.a8(t,s,r,q)
t=p
return t},
L(a,b,c){if(c==null||!(c instanceof A.cj)||c.e!==this)c=A.ef(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ef(s):t).Z(a,b)
s.r.ap(0,c)},
a3(a,b,c,d,e){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ef(s):t).Z(a,b)
s.r.am(c,d,e)},
ak(a,b,c,d,e,f){var t,s=this
if(s.c<1)return
t=s.r;(t==null?s.r=A.ef(s):t).Z(a,b)
s.r.a8(c,d,e,f)},
D(a){return"ImageDataUint4("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){},
gR(){return this.f}}
A.cY.prototype={
bb(a){var t,s=this,r=s.d
if(a)r=new Uint8Array(r.length)
else r=new Uint8Array(A.w(r))
t=s.e
t=t==null?null:t.P()
return new A.cY(r,t,s.a,s.b,s.c)},
gK(){return B.f},
gB(a){return B.e.gB(this.d)},
gI(a){return A.i5(this)},
b4(a,b,c,d,e){return A.aX(A.i5(this),b,c,d,e)},
gt(a){return this.d.byteLength},
gE(){var t=this.e
t=t==null?null:t.gE()
return t==null?255:t},
aI(a,b,c,d){var t=A.l_(B.b.h(B.b.J(a,0,255)),B.b.h(B.b.J(b,0,255)),B.b.h(B.b.J(c,0,255)),B.b.h(B.b.J(d,0,255)))
return t},
L(a,b,c){if(c==null||!(c instanceof A.ck)||c.d!==this)c=A.i5(this)
c.Z(a,b)
return c},
aJ(a,b){return this.L(a,b,null)},
aC(a,b,c){var t,s=this.c,r=b*(this.a*s)+a*s
s=this.d
t=B.b.h(c)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t},
a3(a,b,c,d,e){var t,s,r=this.c,q=b*(this.a*r)+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){r=q+2
o=B.b.h(e)
if(!(r<t))return A.a(p,r)
p[r]=o}}},
ak(a,b,c,d,e,f){var t,s,r=this.c,q=b*(this.a*r)+a*r,p=this.d,o=B.b.h(c)
p.$flags&2&&A.b(p)
t=p.length
if(!(q>=0&&q<t))return A.a(p,q)
p[q]=o
if(r>1){o=q+1
s=B.b.h(d)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>2){o=q+2
s=B.b.h(e)
if(!(o<t))return A.a(p,o)
p[o]=s
if(r>3){r=q+3
o=B.b.h(f)
if(!(r<t))return A.a(p,r)
p[r]=o}}}},
D(a){return"ImageDataUint8("+this.a+", "+this.b+", "+this.c+")"},
aK(a,b){var t,s,r,q,p,o,n,m,l,k,j,i=this,h=null,g=b==null?h:A.az(b,h,B.f,h,h),f=i.c
if(f===1){t=g==null?0:B.a.J(A.u(g.gn()),0,255)
f=i.d
B.e.aB(f,0,f.length,t)}else if(f===2){f=g==null
t=f?0:B.a.J(A.u(g.gn()),0,255)
s=f?0:B.a.J(A.u(g.gp()),0,255)
r=J.kP(B.e.gB(i.d),0,null)
B.Y.aB(r,0,r.length,(s<<8|t)>>>0)}else if(f===4){f=g==null
t=f?0:B.a.J(A.u(g.gn()),0,255)
s=f?0:B.a.J(A.u(g.gp()),0,255)
q=f?0:B.a.J(A.u(g.gq()),0,255)
p=f?0:B.a.J(A.u(g.gu()),0,255)
o=J.aw(B.e.gB(i.d),0,null)
B.o.aB(o,0,o.length,(p<<24|q<<16|s<<8|t)>>>0)}else{f=g==null
t=f?0:B.a.J(A.u(g.gn()),0,255)
s=f?0:B.a.J(A.u(g.gp()),0,255)
q=f?0:B.a.J(A.u(g.gq()),0,255)
for(n=A.i5(i),f=n.d,m=f.c>0,f=f.d,l=f.$flags|0;n.F();){if(m){k=n.c
j=B.b.h(B.a.J(t,0,255))
l&2&&A.b(f)
if(!(k>=0&&k<f.length))return A.a(f,k)
f[k]=j}n.sp(s)
n.sq(q)}}},
gR(){return this.e}}
A.dL.prototype={
ad(){return"Interpolation."+this.b}}
A.aN.prototype={}
A.e5.prototype={
P(){return new A.e5(new Uint16Array(A.w(this.c)),this.a,this.b)},
gK(){return B.C},
gE(){return 1},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=A.I(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=A.I(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=A.I(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=A.I(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t,s
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
t=t[a]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
return s[t]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]
t=$.N
t=t!=null?t:A.U()
if(!(s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.e6.prototype={
P(){return new A.e6(new Float32Array(A.w(this.c)),this.a,this.b)},
gK(){return B.H},
gE(){return 1},
T(a,b,c){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=c}},
b5(a,b,c,d){var t,s,r,q=this.b
a*=q
t=this.c
t.$flags&2&&A.b(t)
s=t.length
if(!(a>=0&&a<s))return A.a(t,a)
t[a]=b
if(q>1){r=a+1
if(!(r<s))return A.a(t,r)
t[r]=c
if(q>2){q=a+2
if(!(q<s))return A.a(t,q)
t[q]=d}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.e7.prototype={
P(){return new A.e7(new Float64Array(A.w(this.c)),this.a,this.b)},
gK(){return B.L},
gE(){return 1},
T(a,b,c){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=c}},
b5(a,b,c,d){var t,s,r,q=this.b
a*=q
t=this.c
t.$flags&2&&A.b(t)
s=t.length
if(!(a>=0&&a<s))return A.a(t,a)
t[a]=b
if(q>1){r=a+1
if(!(r<s))return A.a(t,r)
t[r]=c
if(q>2){q=a+2
if(!(q<s))return A.a(t,q)
t[q]=d}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.e8.prototype={
P(){return new A.e8(new Int16Array(A.w(this.c)),this.a,this.b)},
gK(){return B.N},
gE(){return 32767},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.e9.prototype={
P(){return new A.e9(new Int32Array(A.w(this.c)),this.a,this.b)},
gK(){return B.O},
gE(){return 2147483647},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.ea.prototype={
P(){return new A.ea(new Int8Array(A.w(this.c)),this.a,this.b)},
gK(){return B.M},
gE(){return 127},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.eb.prototype={
P(){return new A.eb(new Uint16Array(A.w(this.c)),this.a,this.b)},
gK(){return B.l},
gE(){return 65535},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.ec.prototype={
P(){return new A.ec(new Uint32Array(A.w(this.c)),this.a,this.b)},
gK(){return B.I},
gE(){return 4294967295},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t
a*=this.b
t=this.c
if(!(a>=0&&a<t.length))return A.a(t,a)
return t[a]},
aN(a){var t,s=this.b
if(s<2)return 0
t=this.c
s=a*s+1
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aM(a){var t,s=this.b
if(s<3)return 0
t=this.c
s=a*s+2
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
aX(a){var t,s=this.b
if(s<4)return 0
t=this.c
s=a*s+3
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.aW.prototype={
P(){return A.lx(this)},
gK(){return B.f},
gE(){return 255},
T(a,b,c){var t,s,r=this.b
if(b<r){t=this.c
r=a*r+b
s=B.a.h(c)
t.$flags&2&&A.b(t)
if(!(r>=0&&r<t.length))return A.a(t,r)
t[r]=s}},
b5(a,b,c,d){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.b.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.b.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){p=a+2
s=B.b.h(d)
if(!(p<r))return A.a(t,p)
t[p]=s}}},
cG(a,b,c,d,e){var t,s,r,q,p=this.b
a*=p
t=this.c
s=B.a.h(b)
t.$flags&2&&A.b(t)
r=t.length
if(!(a>=0&&a<r))return A.a(t,a)
t[a]=s
if(p>1){s=a+1
q=B.a.h(c)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>2){s=a+2
q=B.a.h(d)
if(!(s<r))return A.a(t,s)
t[s]=q
if(p>3){p=a+3
s=B.a.h(e)
if(!(p<r))return A.a(t,p)
t[p]=s}}}},
aW(a,b){var t,s=this.b
if(b<s){t=this.c
s=a*s+b
if(!(s>=0&&s<t.length))return A.a(t,s)
s=t[s]}else s=0
return s},
aO(a){var t,s
a*=this.b
t=this.c
s=t.length
if(a>=s)return 0
if(!(a>=0))return A.a(t,a)
return t[a]},
aN(a){var t,s,r=this.b
if(r<2)return 0
a*=r
r=this.c
t=r.length
if(a>=t)return 0
s=a+1
if(!(s>=0&&s<t))return A.a(r,s)
return r[s]},
aM(a){var t,s,r=this.b
if(r<3)return 0
a*=r
r=this.c
t=r.length
if(a>=t)return 0
s=a+2
if(!(s>=0&&s<t))return A.a(r,s)
return r[s]},
aX(a){var t,s,r=this.b
if(r<4)return 255
a*=r
r=this.c
t=r.length
if(a>=t)return 0
s=a+3
if(!(s>=0&&s<t))return A.a(r,s)
return r[s]},
br(a,b){return this.T(a,0,b)},
bq(a,b){return this.T(a,1,b)},
bp(a,b){return this.T(a,2,b)},
bo(a,b){return this.T(a,3,b)}}
A.c9.prototype={
P(){var t=this
return new A.c9(t.a,t.b,t.c,t.d)},
gK(){return B.C},
gt(a){return this.d.c},
gR(){return null},
gE(){return 1},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=A.I(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=A.I(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s,r=this.d
if(r.c>1){r=r.d
t=this.c+1
s=A.I(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s,r=this.d
if(r.c>2){r=r.d
t=this.c+2
s=A.I(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=$.N
s=s!=null?s:A.U()
if(!(t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=1
return s},
su(a){var t,s,r=this.d
if(r.c>3){r=r.d
t=this.c+3
s=A.I(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gaa(){return this.gn()/1},
saa(a){this.sn(a)},
ga6(){return this.gp()/1},
sa6(a){this.sp(a)},
ga9(){return this.gq()/1},
sa9(a){this.sq(a)},
gU(){return this.gu()/1},
sU(a){this.su(a)},
gaj(){return A.X(this)},
ac(a){var t=this
if(t.d.c>0){t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())}},
am(a,b,c){var t,s,r,q=this,p=q.d,o=p.c
if(o>0){p=p.d
t=q.c
s=A.I(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){t=q.c+1
s=A.I(b)
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>2){o=q.c+2
t=A.I(c)
if(!(o>=0&&o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q=this,p=q.d,o=p.c
if(o>0){p=p.d
t=q.c
s=A.I(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){t=q.c+1
s=A.I(b)
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>2){t=q.c+2
s=A.I(c)
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>3){o=q.c+3
t=A.I(d)
if(!(o>=0&&o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.c9){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.ca.prototype={
P(){var t=this
return new A.ca(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 1},
gK(){return B.H},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=c}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=1
return s},
su(a){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gaa(){return this.gn()/1},
saa(a){this.sn(a)},
ga6(){return this.gp()/1},
sa6(a){this.sp(a)},
ga9(){return this.gq()/1},
sa9(a){this.sq(a)},
gU(){return this.gu()/1},
sU(a){this.su(a)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r=this.d,q=r.d,p=this.c
q.$flags&2&&A.b(q)
t=q.length
if(!(p>=0&&p<t))return A.a(q,p)
q[p]=a
r=r.c
if(r>1){s=p+1
if(!(s<t))return A.a(q,s)
q[s]=b
if(r>2){r=p+2
if(!(r<t))return A.a(q,r)
q[r]=c}}},
a8(a,b,c,d){var t,s,r=this.d,q=r.d,p=this.c
q.$flags&2&&A.b(q)
t=q.length
if(!(p>=0&&p<t))return A.a(q,p)
q[p]=a
r=r.c
if(r>1){s=p+1
if(!(s<t))return A.a(q,s)
q[s]=b
if(r>2){s=p+2
if(!(s<t))return A.a(q,s)
q[s]=c
if(r>3){r=p+3
if(!(r<t))return A.a(q,r)
q[r]=d}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.ca){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.cb.prototype={
P(){var t=this
return new A.cb(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 1},
gK(){return B.L},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=c}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=1
return s},
su(a){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
s.$flags&2&&A.b(s)
if(!(t>=0&&t<s.length))return A.a(s,t)
s[t]=a}},
gaa(){return this.gn()/1},
saa(a){this.sn(a)},
ga6(){return this.gp()/1},
sa6(a){this.sp(a)},
ga9(){return this.gq()/1},
sa9(a){this.sq(a)},
gU(){return this.gu()/1},
sU(a){this.su(a)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r=this.d,q=r.d,p=this.c
q.$flags&2&&A.b(q)
t=q.length
if(!(p>=0&&p<t))return A.a(q,p)
q[p]=a
r=r.c
if(r>1){s=p+1
if(!(s<t))return A.a(q,s)
q[s]=b
if(r>2){r=p+2
if(!(r<t))return A.a(q,r)
q[r]=c}}},
a8(a,b,c,d){var t,s,r=this.d,q=r.d,p=this.c
q.$flags&2&&A.b(q)
t=q.length
if(!(p>=0&&p<t))return A.a(q,p)
q[p]=a
r=r.c
if(r>1){s=p+1
if(!(s<t))return A.a(q,s)
q[s]=b
if(r>2){s=p+2
if(!(s<t))return A.a(q,s)
q[s]=c
if(r>3){r=p+3
if(!(r<t))return A.a(q,r)
q[r]=d}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.cb){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.cc.prototype={
P(){var t=this
return new A.cc(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 32767},
gK(){return B.N},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s,r=this.d
if(r.c>1){r=r.d
t=this.c+1
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s,r=this.d
if(r.c>2){r=r.d
t=this.c+2
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=32767
return s},
su(a){var t,s,r=this.d
if(r.c>3){r=r.d
t=this.c+3
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gaa(){return this.gn()/32767},
saa(a){this.sn(a*32767)},
ga6(){return this.gp()/32767},
sa6(a){this.sp(a*32767)},
ga9(){return this.gq()/32767},
sa9(a){this.sq(a*32767)},
gU(){return this.gu()/32767},
sU(a){this.su(a*32767)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.cc){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.cd.prototype={
P(){var t=this
return new A.cd(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 2147483647},
gK(){return B.O},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s,r=this.d
if(r.c>1){r=r.d
t=this.c+1
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s,r=this.d
if(r.c>2){r=r.d
t=this.c+2
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=2147483647
return s},
su(a){var t,s,r=this.d
if(r.c>3){r=r.d
t=this.c+3
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gaa(){return this.gn()/2147483647},
saa(a){this.sn(a*2147483647)},
ga6(){return this.gp()/2147483647},
sa6(a){this.sp(a*2147483647)},
ga9(){return this.gq()/2147483647},
sa9(a){this.sq(a*2147483647)},
gU(){return this.gu()/2147483647},
sU(a){this.su(a*2147483647)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.cd){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.ce.prototype={
P(){var t=this
return new A.ce(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 127},
gK(){return B.M},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s,r=this.d
if(r.c>1){r=r.d
t=this.c+1
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s,r=this.d
if(r.c>2){r=r.d
t=this.c+2
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=127
return s},
su(a){var t,s,r=this.d
if(r.c>3){r=r.d
t=this.c+3
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gaa(){return this.gn()/127},
saa(a){this.sn(a*127)},
ga6(){return this.gp()/127},
sa6(a){this.sp(a*127)},
ga9(){return this.gq()/127},
sa9(a){this.sq(a*127)},
gU(){return this.gu()/127},
sU(a){this.su(a*127)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.ce){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.fH.prototype={
F(){var t=this,s=t.a
if(s.gaL()+1>t.d){s.Z(t.b,s.gaH()+1)
return s.gaH()<=t.e}return s.F()},
gM(){return this.a},
$iA:1}
A.cf.prototype={
P(){var t=this
return new A.cf(t.a,t.b,t.c,t.d,t.e,t.f)},
gt(a){var t=this.f,s=t.f
s=s==null?null:s.b
return s==null?t.c:s},
gR(){return this.f.f},
gE(){return this.f.gE()},
gK(){return B.w},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.f
s=b*t.e
r.e=s
t=a*t.c
r.c=s+B.a.j(t,3)
r.d=t&7},
gM(){return this},
F(){var t,s=this,r=++s.a,q=s.f
if(r===q.a){s.a=0
r=++s.b
s.d=0;++s.c
s.e=s.e+q.e
return r<q.b}t=q.c
if(q.f!=null||t===1){if(++s.d>7){s.d=0;++s.c}}else{r*=t
s.d=r&7
s.c=s.e+B.a.j(r,3)}r=s.c
q=q.d
q===$&&A.d()
return r<q.byteLength},
dv(a){var t,s,r=this.c,q=7-(this.d+a)
if(q<0){q+=8;++r}t=this.f.d
t===$&&A.d()
s=t.length
if(r>=s)return 0
if(!(r>=0))return A.a(t,r)
return B.a.a0(t[r],q)&1},
b7(a){var t=this.f,s=t.f
if(s==null)t=t.c>a?this.dv(a):0
else t=s.aW(this.dv(0),a)
return t},
an(a,b){var t,s,r,q,p,o,n=this.f
if(a>=n.c)return
t=this.c
s=7-(this.d+a)
if(s<0){++t
s+=8}r=n.d
r===$&&A.d()
if(!(t>=0&&t<r.length))return A.a(r,t)
q=r[t]
p=B.a.J(B.b.h(b),0,1)
if(!(s>=0&&s<8))return A.a(B.bp,s)
o=B.bp[s]
r=B.a.W(p,s)
n=n.d
n.$flags&2&&A.b(n)
if(!(t<n.length))return A.a(n,t)
n[t]=(q&o|r)>>>0},
k(a,b){return this.b7(b)},
i(a,b,c){return this.an(b,c)},
gN(){return this.dv(0)},
sN(a){this.an(0,a)},
gn(){return this.b7(0)},
sn(a){this.an(0,a)},
gp(){return this.b7(1)},
sp(a){this.an(1,a)},
gq(){return this.b7(2)},
sq(a){this.an(2,a)},
gu(){var t=this.f
return t.f==null&&t.c<4?t.gE():this.b7(3)},
su(a){this.an(3,a)},
gaa(){return this.b7(0)/this.f.gE()},
saa(a){this.an(0,a*this.f.gE())},
ga6(){return this.b7(1)/this.f.gE()},
sa6(a){this.an(1,a*this.f.gE())},
ga9(){return this.b7(2)/this.f.gE()},
sa9(a){this.an(2,a*this.f.gE())},
gU(){return this.gu()/this.f.gE()},
sU(a){this.an(3,a*this.f.gE())},
gaj(){return A.X(this)},
ac(a){var t=this
t.an(0,a.gn())
t.an(1,a.gp())
t.an(2,a.gq())
t.an(3,a.gu())},
am(a,b,c){var t=this,s=t.f.c
if(s>0){t.an(0,a)
if(s>1){t.an(1,b)
if(s>2)t.an(2,c)}}},
a8(a,b,c,d){var t=this,s=t.f.c
if(s>0){t.an(0,a)
if(s>1){t.an(1,b)
if(s>2){t.an(2,c)
if(s>3)t.an(3,d)}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q=this
if(b==null)return!1
if(b instanceof A.cf){t=A.q(q,A.l(q).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=q.f
s=t.f
r=s!=null?s.b:t.c
t=J.S(b)
if(t.gt(b)!==r)return!1
if(q.b7(0)!==t.k(b,0))return!1
if(r>1){if(q.b7(1)!==t.k(b,1))return!1
if(r>2){if(q.b7(2)!==t.k(b,2))return!1
if(r>3)if(q.b7(3)!==t.k(b,3))return!1}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.f}}
A.cg.prototype={
P(){var t=this
return new A.cg(t.a,t.b,t.c,t.d)},
gt(a){var t=this.d,s=t.e
s=s==null?null:s.b
return s==null?t.c:s},
gR(){return this.d.e},
gE(){return this.d.gE()},
gK(){return B.l},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c
t+=r.e==null?r.c:1
s.c=t
return t<r.d.length},
bi(a){var t,s=this.d,r=s.e
if(r!=null){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=r.aW(s[t],a)
s=t}else if(a<s.c){s=s.d
r=this.c+a
if(!(r>=0&&r<s.length))return A.a(s,r)
r=s[r]
s=r}else s=0
return s},
k(a,b){return this.bi(b)},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d,r=s.e
if(r==null)if(s.c>0){s=s.d
r=this.c
if(!(r>=0&&r<s.length))return A.a(s,r)
r=s[r]
s=r}else s=0
else{s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=r.aO(s[t])
s=t}return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>1){r=r.d
q=s.c+1
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=0}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aN(r[t])
r=t}return r},
sp(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>1){s=s.d
r=this.c+1
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gq(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>2){r=r.d
q=s.c+2
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=0}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aM(r[t])
r=t}return r},
sq(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>2){s=s.d
r=this.c+2
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gu(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c+1
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>3){r=r.d
q=s.c+3
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=r.gE()}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aX(r[t])
r=t}return r},
su(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c+1
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>3){s=s.d
r=this.c+3
t=B.b.h(a)
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gaa(){return this.gn()/this.d.gE()},
saa(a){this.sn(a*this.d.gE())},
ga6(){return this.gp()/this.d.gE()},
sa6(a){this.sp(a*this.d.gE())},
ga9(){return this.gq()/this.d.gE()},
sa9(a){this.sq(a*this.d.gE())},
gU(){return this.gu()/this.d.gE()},
sU(a){this.su(a*this.d.gE())},
gaj(){return this.d.c===2?this.gn():A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q=this
if(b==null)return!1
if(b instanceof A.cg){t=A.q(q,A.l(q).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=q.d
s=t.e
r=s!=null?s.b:t.c
t=J.S(b)
if(t.gt(b)!==r)return!1
if(q.bi(0)!==t.k(b,0))return!1
if(r>1){if(q.bi(1)!==t.k(b,1))return!1
if(r>2){if(q.bi(2)!==t.k(b,2))return!1
if(r>3)if(q.bi(3)!==t.k(b,3))return!1}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.ch.prototype={
P(){var t=this
return new A.ch(t.a,t.b,t.c,t.d,t.e,t.f)},
gt(a){var t=this.f,s=t.f
s=s==null?null:s.b
return s==null?t.c:s},
gR(){return this.f.f},
gE(){return this.f.gE()},
gK(){return B.y},
geW(){var t=this.f
return t.f!=null?2:t.c<<1>>>0},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r,q=this
q.a=a
q.b=b
t=q.geW()
s=b*q.f.e
q.e=s
r=a*t
q.c=s+B.a.j(r,3)
q.d=r&7},
gM(){return this},
F(){var t=this,s=++t.a,r=t.f
if(s===r.a){t.a=0
s=++t.b
t.d=0;++t.c
t.e=t.e+r.e
return s<r.b}if(r.f!=null||r.c===1){if((t.d+=2)>7){t.d=0;++t.c}}else{s*=t.geW()
t.d=s&7
t.c=t.e+B.a.j(s,3)}s=t.c
r=r.d
r===$&&A.d()
return s<r.length},
dw(a){var t,s=this.c,r=6-(this.d+(a<<1>>>0))
if(r<0){r+=8;++s}t=this.f.d
t===$&&A.d()
if(!(s>=0&&s<t.length))return A.a(t,s)
return B.a.a0(t[s],r)&3},
b8(a){var t=this.f,s=t.f
if(s==null)t=t.c>a?this.dw(a):0
else t=s.aW(this.dw(0),a)
return t},
ao(a,b){var t,s,r,q,p,o,n=this.f
if(a>=n.c)return
t=this.c
s=6-(this.d+(a<<1>>>0))
if(s<0){++t
s+=8}r=n.d
r===$&&A.d()
if(!(t>=0&&t<r.length))return A.a(r,t)
q=r[t]
p=B.a.J(B.b.h(b),0,3)
r=B.a.j(s,1)
if(!(r<4))return A.a(B.b7,r)
o=B.b7[r]
r=B.a.W(p,s)
n=n.d
n.$flags&2&&A.b(n)
if(!(t<n.length))return A.a(n,t)
n[t]=(q&o|r)>>>0},
k(a,b){return this.b8(b)},
i(a,b,c){return this.ao(b,c)},
gN(){return this.dw(0)},
sN(a){this.ao(0,a)},
gn(){return this.b8(0)},
sn(a){this.ao(0,a)},
gp(){return this.b8(1)},
sp(a){this.ao(1,a)},
gq(){return this.b8(2)},
sq(a){this.ao(2,a)},
gu(){var t=this.f
return t.f==null&&t.c<4?t.gE():this.b8(3)},
su(a){this.ao(3,a)},
gaa(){return this.b8(0)/this.f.gE()},
saa(a){this.ao(0,a*this.f.gE())},
ga6(){return this.b8(1)/this.f.gE()},
sa6(a){this.ao(1,a*this.f.gE())},
ga9(){return this.b8(2)/this.f.gE()},
sa9(a){this.ao(2,a*this.f.gE())},
gU(){return this.gu()/this.f.gE()},
sU(a){this.ao(3,a*this.f.gE())},
gaj(){return A.X(this)},
ac(a){var t=this
t.ao(0,a.gn())
t.ao(1,a.gp())
t.ao(2,a.gq())
t.ao(3,a.gu())},
am(a,b,c){var t=this,s=t.f.c
if(s>0){t.ao(0,a)
if(s>1){t.ao(1,b)
if(s>2)t.ao(2,c)}}},
a8(a,b,c,d){var t=this,s=t.f.c
if(s>0){t.ao(0,a)
if(s>1){t.ao(1,b)
if(s>2){t.ao(2,c)
if(s>3)t.ao(3,d)}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q=this
if(b==null)return!1
if(b instanceof A.ch){t=A.q(q,A.l(q).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=q.f
s=t.f
r=s!=null?s.b:t.c
t=J.S(b)
if(t.gt(b)!==r)return!1
if(q.b8(0)!==t.k(b,0))return!1
if(r>1){if(q.b8(1)!==t.k(b,1))return!1
if(r>2){if(q.b8(2)!==t.k(b,2))return!1
if(r>3)if(q.b8(3)!==t.k(b,3))return!1}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.f}}
A.ci.prototype={
P(){var t=this
return new A.ci(t.a,t.b,t.c,t.d)},
gt(a){return this.d.c},
gR(){return null},
gE(){return 4294967295},
gK(){return B.I},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c+r.c
s.c=t
return t<r.d.length},
k(a,b){var t,s=this.d
if(b<s.c){s=s.d
t=this.c+b
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(c)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){return this.gn()},
sN(a){this.sn(a)},
gn(){var t,s=this.d
if(s.c>0){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this.d
if(s.c>1){s=s.d
t=this.c+1
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sp(a){var t,s,r=this.d
if(r.c>1){r=r.d
t=this.c+1
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gq(){var t,s=this.d
if(s.c>2){s=s.d
t=this.c+2
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=0
return s},
sq(a){var t,s,r=this.d
if(r.c>2){r=r.d
t=this.c+2
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gu(){var t,s=this.d
if(s.c>3){s=s.d
t=this.c+3
if(!(t>=0&&t<s.length))return A.a(s,t)
t=s[t]
s=t}else s=4294967295
return s},
su(a){var t,s,r=this.d
if(r.c>3){r=r.d
t=this.c+3
s=B.b.h(a)
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gaa(){return this.gn()/4294967295},
saa(a){this.sn(a*4294967295)},
ga6(){return this.gp()/4294967295},
sa6(a){this.sp(a*4294967295)},
ga9(){return this.gq()/4294967295},
sa9(a){this.sq(a*4294967295)},
gU(){return this.gu()/4294967295},
sU(a){this.su(a*4294967295)},
gaj(){return A.X(this)},
ac(a){var t=this
t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q,p,o=this
if(b==null)return!1
if(b instanceof A.ci){t=A.q(o,A.l(o).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=J.S(b)
s=o.d
r=s.c
if(t.gt(b)!==r)return!1
s=s.d
q=o.c
p=s.length
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,0))return!1
if(r>1){q=o.c+1
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,1))return!1
if(r>2){q=o.c+2
if(!(q>=0&&q<p))return A.a(s,q)
if(s[q]!==t.k(b,2))return!1
if(r>3){r=o.c+3
if(!(r>=0&&r<p))return A.a(s,r)
if(s[r]!==t.k(b,3))return!1}}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.cj.prototype={
P(){var t=this
return new A.cj(t.a,t.b,t.c,t.d,t.e)},
gt(a){var t=this.e,s=t.f
s=s==null?null:s.b
return s==null?t.c:s},
gR(){return this.e.f},
gE(){return this.e.gE()},
gK(){return B.z},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r,q=this
q.a=a
q.b=b
t=q.e
s=t.c*4
r=t.e
if(s===4)t=b*r+B.a.j(a,1)
else if(s===8)t=b*t.a+a
else{t=b*r
t=s===16?t+(a<<1>>>0):t+B.a.j(a*s,3)}q.c=t
t=a*s
q.d=s>7?t&4:t&7},
gM(){return this},
F(){var t,s,r,q=this,p=q.e
if(++q.a===p.a){q.a=0
t=++q.b
q.d=0
q.c=t*p.e
return t<p.b}s=p.c
t=p.f!=null||s===1
r=q.d
if(t){t=r+4
q.d=t
if(t>7){q.d=0;++q.c}}else{t=q.d=r+(s<<2>>>0)
while(t>7){t-=8
q.d=t;++q.c}}t=q.c
p=p.d
p===$&&A.d()
return t<p.length},
dm(a){var t,s=this.c,r=4-(this.d+(a<<2>>>0))
if(r<0){r+=8;++s}t=this.e.d
t===$&&A.d()
if(!(s>=0&&s<t.length))return A.a(t,s)
return B.a.a0(t[s],r)&15},
b9(a){var t=this.e,s=t.f
if(s==null)t=t.c>a?this.dm(a):0
else t=s.aW(this.dm(0),a)
return t},
ap(a,b){var t,s,r,q,p,o,n=this.e
if(a>=n.c)return
t=this.c
s=4-(this.d+(a<<2>>>0))
if(s<0){s+=8;++t}r=n.d
r===$&&A.d()
if(!(t>=0&&t<r.length))return A.a(r,t)
q=r[t]
p=B.a.J(B.b.h(b),0,15)
o=s===4?15:240
r=B.a.W(p,s)
n=n.d
n.$flags&2&&A.b(n)
if(!(t<n.length))return A.a(n,t)
n[t]=(q&o|r)>>>0},
k(a,b){return this.b9(b)},
i(a,b,c){return this.ap(b,c)},
gN(){return this.dm(0)},
sN(a){this.ap(0,a)},
gn(){return this.b9(0)},
sn(a){this.ap(0,a)},
gp(){return this.b9(1)},
sp(a){this.ap(1,a)},
gq(){return this.b9(2)},
sq(a){this.ap(2,a)},
gu(){var t=this.e
return t.f==null&&t.c<4?t.gE():this.b9(3)},
su(a){this.ap(3,a)},
gaa(){return this.b9(0)/this.e.gE()},
saa(a){this.ap(0,a*this.e.gE())},
ga6(){return this.b9(1)/this.e.gE()},
sa6(a){this.ap(1,a*this.e.gE())},
ga9(){return this.b9(2)/this.e.gE()},
sa9(a){this.ap(2,a*this.e.gE())},
gU(){return this.gu()/this.e.gE()},
sU(a){this.ap(3,a*this.e.gE())},
gaj(){return A.X(this)},
ac(a){var t=this
t.ap(0,a.gn())
t.ap(1,a.gp())
t.ap(2,a.gq())
t.ap(3,a.gu())},
am(a,b,c){var t=this,s=t.e.c
if(s>0){t.ap(0,a)
if(s>1){t.ap(1,b)
if(s>2)t.ap(2,c)}}},
a8(a,b,c,d){var t=this,s=t.e.c
if(s>0){t.ap(0,a)
if(s>1){t.ap(1,b)
if(s>2){t.ap(2,c)
if(s>3)t.ap(3,d)}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q=this
if(b==null)return!1
if(b instanceof A.cj){t=A.q(q,A.l(q).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){r=q.e.c
t=J.S(b)
if(t.gt(b)!==r)return!1
if(q.b9(0)!==t.k(b,0))return!1
if(r>1){if(q.b9(1)!==t.k(b,1))return!1
if(r>2){if(q.b9(2)!==t.k(b,2))return!1
if(r>3)if(q.b9(3)!==t.k(b,3))return!1}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.e}}
A.ck.prototype={
P(){var t=this
return new A.ck(t.a,t.b,t.c,t.d)},
gt(a){var t=this.d,s=t.e
s=s==null?null:s.b
return s==null?t.c:s},
gR(){return this.d.e},
gE(){return this.d.gE()},
gK(){return B.f},
gaL(){return this.a},
gaH(){return this.b},
Z(a,b){var t,s,r=this
r.a=a
r.b=b
t=r.d
s=t.c
r.c=b*t.a*s+a*s},
gM(){return this},
F(){var t,s=this,r=s.d
if(++s.a===r.a){s.a=0
if(++s.b===r.b)return!1}t=s.c
t+=r.e==null?r.c:1
s.c=t
return t<r.d.length},
bi(a){var t,s=this.d,r=s.e
if(r!=null){s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=r.aW(s[t],a)
s=t}else if(a<s.c){s=s.d
r=this.c+a
if(!(r>=0&&r<s.length))return A.a(s,r)
r=s[r]
s=r}else s=0
return s},
k(a,b){return this.bi(b)},
i(a,b,c){var t,s,r=this.d
if(b<r.c){r=r.d
t=this.c+b
s=B.b.h(B.b.J(c,0,255))
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gN(){var t=this.d.d,s=this.c
if(!(s>=0&&s<t.length))return A.a(t,s)
return t[s]},
sN(a){var t=this.d.d,s=this.c,r=B.b.h(B.b.J(a,0,255))
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=r},
gn(){var t,s=this.d,r=s.e
if(r==null)if(s.c>0){s=s.d
r=this.c
if(!(r>=0&&r<s.length))return A.a(s,r)
r=s[r]
s=r}else s=0
else{s=s.d
t=this.c
if(!(t>=0&&t<s.length))return A.a(s,t)
t=r.aO(s[t])
s=t}return s},
sn(a){var t,s,r=this.d
if(r.c>0){r=r.d
t=this.c
s=B.b.h(B.b.J(a,0,255))
r.$flags&2&&A.b(r)
if(!(t>=0&&t<r.length))return A.a(r,t)
r[t]=s}},
gp(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>1){r=r.d
q=s.c+1
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=0}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aN(r[t])
r=t}return r},
sp(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>1){s=s.d
r=this.c+1
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gq(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>2){r=r.d
q=s.c+2
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=0}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aM(r[t])
r=t}return r},
sq(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>2){s=s.d
r=this.c+2
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gu(){var t,s=this,r=s.d,q=r.e
if(q==null){q=r.c
if(q===2){r=r.d
q=s.c+1
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else if(q>3){r=r.d
q=s.c+3
if(!(q>=0&&q<r.length))return A.a(r,q)
q=r[q]
r=q}else r=255}else{r=r.d
t=s.c
if(!(t>=0&&t<r.length))return A.a(r,t)
t=q.aX(r[t])
r=t}return r},
su(a){var t,s=this.d,r=s.c
if(r===2){s=s.d
r=this.c+1
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}else if(r>3){s=s.d
r=this.c+3
t=B.b.h(B.b.J(a,0,255))
s.$flags&2&&A.b(s)
if(!(r>=0&&r<s.length))return A.a(s,r)
s[r]=t}},
gaa(){return this.gn()/this.d.gE()},
saa(a){this.sn(a*this.d.gE())},
ga6(){return this.gp()/this.d.gE()},
sa6(a){this.sp(a*this.d.gE())},
ga9(){return this.gq()/this.d.gE()},
sa9(a){this.sq(a*this.d.gE())},
gU(){return this.gu()/this.d.gE()},
sU(a){this.su(a*this.d.gE())},
gaj(){return this.d.c===2?this.gn():A.X(this)},
ac(a){var t=this
if(t.d.e!=null)t.sN(a.gN())
else{t.sn(a.gn())
t.sp(a.gp())
t.sq(a.gq())
t.su(a.gu())}},
am(a,b,c){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){o=t+2
t=B.a.h(c)
if(!(o<r))return A.a(p,o)
p[o]=t}}}},
a8(a,b,c,d){var t,s,r,q,p=this.d,o=p.c
if(o>0){p=p.d
t=this.c
s=B.a.h(a)
p.$flags&2&&A.b(p)
r=p.length
if(!(t>=0&&t<r))return A.a(p,t)
p[t]=s
if(o>1){s=t+1
q=B.a.h(b)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>2){s=t+2
q=B.a.h(c)
if(!(s<r))return A.a(p,s)
p[s]=q
if(o>3){o=t+3
t=B.a.h(d)
if(!(o<r))return A.a(p,o)
p[o]=t}}}}},
gI(a){return new A.L(this)},
S(a,b){var t,s,r,q=this
if(b==null)return!1
if(b instanceof A.ck){t=A.q(q,A.l(q).v("e.E"))
t=A.m(t)
s=A.q(b,A.l(b).v("e.E"))
return t===A.m(s)}if(u.L.b(b)){t=q.d
s=t.e
r=s!=null?s.b:t.c
t=J.S(b)
if(t.gt(b)!==r)return!1
if(q.bi(0)!==t.k(b,0))return!1
if(r>1){if(q.bi(1)!==t.k(b,1))return!1
if(r>2){if(q.bi(2)!==t.k(b,2))return!1
if(r>3)if(q.bi(3)!==t.k(b,3))return!1}}return!0}return!1},
gH(a){var t=A.q(this,A.l(this).v("e.E"))
return A.m(t)},
b1(a){return A.az(this,null,a,null,null)},
$iA:1,
$iy:1,
$it:1,
gb2(){return this.d}}
A.G.prototype={
P(){return new A.G()},
gb2(){return $.mr()},
gaL(){return 0},
gaH(){return 0},
gt(a){return 0},
gE(){return 0},
gK(){return B.f},
gR(){return null},
k(a,b){return 0},
i(a,b,c){},
gN(){return 0},
sN(a){},
gn(){return 0},
sn(a){},
gp(){return 0},
sp(a){},
gq(){return 0},
sq(a){},
gu(){return 0},
su(a){},
gaa(){return 0},
saa(a){},
ga6(){return 0},
sa6(a){},
ga9(){return 0},
sa9(a){},
gU(){return 0},
sU(a){},
gaj(){return 0},
ac(a){},
am(a,b,c){},
a8(a,b,c,d){},
Z(a,b){},
gM(){return this},
F(){return!1},
S(a,b){if(b==null)return!1
return b instanceof A.G},
gH(a){return 0},
gI(a){return new A.L(this)},
b1(a){return this},
$iA:1,
$iy:1,
$it:1}
A.hA.prototype={
ad(){return"FlipDirection."+this.b}}
A.hM.prototype={
D(a){return"ImageException: "+this.a}}
A.aa.prototype={
gt(a){return this.c-this.d},
i(a,b,c){J.x(this.a,this.d+b,c)
return c},
bd(a,b,c,d){var t=this.a,s=J.aI(t),r=this.d+a
if(c instanceof A.aa)s.ar(t,r,r+b,c.a,c.d+d)
else s.ar(t,r,r+b,u.L.a(c),d)},
bR(a,b,c){return this.bd(a,b,c,0)},
jl(a,b,c){var t=this.a,s=this.d+a
J.b9(t,s,s+b,c)},
dc(a,b,c){var t=this,s=c!=null?t.b+c:t.d
return A.v(t.a,t.e,a,s+b)},
ai(a){return this.dc(a,0,null)},
bU(a,b){return this.dc(a,0,b)},
cH(a,b){return this.dc(a,b,null)},
G(){return J.c(this.a,this.d++)},
ag(a){var t=this.ai(a)
this.d=this.d+(t.c-t.d)
return t},
ah(a){var t,s,r,q,p,o=this
if(a==null){t=A.j([],u.t)
for(s=o.c;r=o.d,r<s;){q=o.a
o.d=r+1
p=J.c(q,r)
if(p===0)return A.en(t,0,null)
B.c.A(t,p)}throw A.f(A.n("EOF reached without finding string terminator (length: "+A.z(a)+")"))}return A.en(o.ag(a).a2(),0,null)},
cv(){return this.ah(null)},
fc(a){var t,s,r,q,p=this,o=A.j([],u.t)
for(t=p.c;s=p.d,s<t;){r=p.a
p.d=s+1
q=J.c(r,s)
B.c.A(o,q)
if(q===10||o.length>=a)return A.en(o,0,null)}return A.en(o,0,null)},
js(){return this.fc(256)},
jt(){var t,s,r,q,p=this,o=A.j([],u.t)
for(t=p.c;s=p.d,s<t;){r=p.a
p.d=s+1
q=J.c(r,s)
if(q===0){u.L.a(o)
return new A.hi(!0).e4(o,0,null,!0)}B.c.A(o,q)}return B.aQ.f_(o,!0)},
m(){var t=this,s=J.c(t.a,t.d++)&255,r=J.c(t.a,t.d++)&255
if(t.e)return s<<8|r
return r<<8|s},
bf(){var t=this,s=J.c(t.a,t.d++)&255,r=J.c(t.a,t.d++)&255,q=J.c(t.a,t.d++)&255
if(t.e)return q|r<<8|s<<16
return s|r<<8|q<<16},
l(){var t=this,s=J.c(t.a,t.d++)&255,r=J.c(t.a,t.d++)&255,q=J.c(t.a,t.d++)&255,p=J.c(t.a,t.d++)&255
if(t.e)return(s<<24|r<<16|q<<8|p)>>>0
return(p<<24|q<<16|r<<8|s)>>>0},
d6(){return A.qp(this.dL())},
dL(){var t=this,s=J.c(t.a,t.d++)&255,r=J.c(t.a,t.d++)&255,q=J.c(t.a,t.d++)&255,p=J.c(t.a,t.d++)&255,o=J.c(t.a,t.d++)&255,n=J.c(t.a,t.d++)&255,m=J.c(t.a,t.d++)&255,l=J.c(t.a,t.d++)&255
if(t.e)return(B.a.O(s,56)|B.a.O(r,48)|B.a.O(q,40)|B.a.O(p,32)|o<<24|n<<16|m<<8|l)>>>0
return(B.a.O(l,56)|B.a.O(m,48)|B.a.O(n,40)|B.a.O(o,32)|p<<24|q<<16|r<<8|s)>>>0},
cw(a,b,c){var t,s=this,r=s.a
if(u.D.b(r))return s.fg(b,c)
t=s.b+s.d+b
return J.jN(r,t,c<=0?s.c:t+c)},
fg(a,b){var t,s=this,r=b==null?s.c-s.d-a:b,q=s.a
if(u.D.b(q))return J.V(B.e.gB(q),q.byteOffset+s.d+a,r)
t=s.d+a
t=J.jN(q,t,t+r)
return new Uint8Array(A.w(t))},
a2(){return this.fg(0,null)},
cz(){var t=this.a
if(u.D.b(t))return J.aw(B.e.gB(t),t.byteOffset+this.d,null)
return J.aw(B.e.gB(this.a2()),0,null)},
sB(a,b){this.a=u.L.a(b)}}
A.i4.prototype={
C(a){var t,s,r=this
if(r.a===r.c.length)r.hG()
t=r.c
s=r.a++
t.$flags&2&&A.b(t)
if(!(s>=0&&s<t.length))return A.a(t,s)
t[s]=a&255},
aV(a){var t,s,r,q,p,o=this
u.L.a(a)
t=J.ao(a)
while(s=o.a,r=s+t,q=o.c,p=q.length,r>p)o.ee(r-p)
B.e.bk(q,s,r,a)
o.a+=t},
aw(a){var t=this
if(t.b){t.C(B.a.j(a,8)&255)
t.C(a&255)
return}t.C(a&255)
t.C(B.a.j(a,8)&255)},
aF(a){var t=this
if(t.b){t.C(B.a.j(a,24)&255)
t.C(B.a.j(a,16)&255)
t.C(B.a.j(a,8)&255)
t.C(a&255)
return}t.C(a&255)
t.C(B.a.j(a,8)&255)
t.C(B.a.j(a,16)&255)
t.C(B.a.j(a,24)&255)},
jF(a){var t,s,r=this,q=new Float32Array(1)
q[0]=a
t=J.V(B.ai.gB(q),0,null)
if(r.b){if(3>=t.length)return A.a(t,3)
r.C(t[3])
r.C(t[2])
r.C(t[1])
r.C(t[0])
return}s=t.length
if(0>=s)return A.a(t,0)
r.C(t[0])
if(1>=s)return A.a(t,1)
r.C(t[1])
if(2>=s)return A.a(t,2)
r.C(t[2])
if(3>=s)return A.a(t,3)
r.C(t[3])},
jG(a){var t,s,r=this,q=new Float64Array(1)
q[0]=a
t=J.V(B.aj.gB(q),0,null)
if(r.b){if(7>=t.length)return A.a(t,7)
r.C(t[7])
r.C(t[6])
r.C(t[5])
r.C(t[4])
r.C(t[3])
r.C(t[2])
r.C(t[1])
r.C(t[0])
return}s=t.length
if(0>=s)return A.a(t,0)
r.C(t[0])
if(1>=s)return A.a(t,1)
r.C(t[1])
if(2>=s)return A.a(t,2)
r.C(t[2])
if(3>=s)return A.a(t,3)
r.C(t[3])
if(4>=s)return A.a(t,4)
r.C(t[4])
if(5>=s)return A.a(t,5)
r.C(t[5])
if(6>=s)return A.a(t,6)
r.C(t[6])
if(7>=s)return A.a(t,7)
r.C(t[7])},
ee(a){var t,s,r,q
if(a!=null)t=a
else{s=this.c.length
t=s===0?8192:s*2}s=this.c
r=s.length
q=new Uint8Array(r+t)
B.e.bk(q,0,r,s)
this.c=q},
hG(){return this.ee(null)},
gt(a){return this.a}}
A.d9.prototype={
h(a){var t=this.b
return t===0?0:B.a.au(this.a,t)},
S(a,b){if(b==null)return!1
return b instanceof A.d9&&this.a===b.a&&this.b===b.b},
gH(a){return A.nB(this.a,this.b,B.a3,B.a3)},
D(a){return""+this.a+"/"+this.b}}
A.j8.prototype={
$2(a,b){var t=J.ac(a),s=J.ac(b)
this.a.i(0,t,s)
return s},
$S:6};(function aliases(){var t=J.bB.prototype
t.fC=t.D
t=A.F.prototype
t.dT=t.ar})();(function installTearOffs(){var t=hunkHelpers._static_2,s=hunkHelpers._instance_1i,r=hunkHelpers._static_1,q=hunkHelpers.installInstanceTearOff,p=hunkHelpers._instance_2u,o=hunkHelpers.installStaticTearOff
t(J,"pg","lm",33)
s(A.bU.prototype,"giX","aR",27)
r(A,"pW","p5",9)
q(A.a0.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.bg.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.c3.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.aU.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.c_.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.by.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.c2.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.c0.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.c1.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
q(A.cO.prototype,"gby",1,0,null,["$1","$0"],["a4","h"],2,0,0)
var n
p(n=A.fA.prototype,"ghi","hj",4)
p(n,"ghl","hm",4)
p(n,"ghn","ho",4)
p(n,"ghc","hd",4)
p(n,"ghe","hf",4)
r(A,"qz","nZ",0)
r(A,"qs","nR",0)
r(A,"qq","nP",0)
r(A,"qx","nX",0)
r(A,"qy","nY",0)
r(A,"qw","nW",0)
r(A,"qv","nV",0)
r(A,"qu","nU",0)
r(A,"qB","o0",0)
r(A,"qA","o_",0)
r(A,"qt","nS",0)
r(A,"qr","nQ",0)
r(A,"qM","ob",0)
r(A,"qK","o9",0)
r(A,"qC","o1",0)
r(A,"qE","o3",0)
r(A,"qD","o2",0)
r(A,"qF","o4",0)
r(A,"qN","oc",0)
r(A,"qL","oa",0)
r(A,"qG","o5",0)
r(A,"qH","o6",0)
r(A,"qI","o7",0)
r(A,"qJ","o8",0)
p(A.ev.prototype,"gih","ii",14)
p(A.ft.prototype,"gja","jb",14)
o(A,"kI",3,null,["$3"],["od"],1,0)
o(A,"qO",3,null,["$3"],["oe"],1,0)
o(A,"qT",3,null,["$3"],["oj"],1,0)
o(A,"qU",3,null,["$3"],["ok"],1,0)
o(A,"qV",3,null,["$3"],["ol"],1,0)
o(A,"qW",3,null,["$3"],["om"],1,0)
o(A,"qX",3,null,["$3"],["on"],1,0)
o(A,"qY",3,null,["$3"],["oo"],1,0)
o(A,"qZ",3,null,["$3"],["op"],1,0)
o(A,"r_",3,null,["$3"],["oq"],1,0)
o(A,"qP",3,null,["$3"],["of"],1,0)
o(A,"qQ",3,null,["$3"],["og"],1,0)
o(A,"qR",3,null,["$3"],["oh"],1,0)
o(A,"qS",3,null,["$3"],["oi"],1,0)
q(A.bh.prototype,"gfs",0,5,null,["$5"],["a3"],3,0,0)
t(A,"kF","pw",36)
o(A,"r1",6,null,["$6"],["ox"],8,0)
o(A,"r2",6,null,["$6"],["oy"],8,0)
o(A,"r0",6,null,["$6"],["ow"],8,0)})();(function inheritance(){var t=hunkHelpers.mixin,s=hunkHelpers.inherit,r=hunkHelpers.inheritMany
s(A.H,null)
r(A.H,[A.k0,J.fk,A.el,J.bR,A.iI,A.T,A.F,A.ie,A.e,A.bk,A.eA,A.dr,A.ax,A.bp,A.cK,A.cq,A.bG,A.il,A.i3,A.bv,A.ai,A.i_,A.O,A.aq,A.fZ,A.iR,A.iH,A.iV,A.b_,A.hd,A.hh,A.hg,A.eC,A.eZ,A.bS,A.iP,A.iY,A.hi,A.iJ,A.fF,A.em,A.iK,A.hC,A.e1,A.cm,A.hG,A.hF,A.a7,A.iM,A.iL,A.ha,A.aF,A.hH,A.iG,A.hP,A.iF,A.fj,A.fG,A.L,A.aK,A.hc,A.f1,A.aC,A.a0,A.ht,A.bc,A.hv,A.J,A.hx,A.f2,A.be,A.f3,A.f4,A.f5,A.dt,A.eH,A.dw,A.dx,A.dy,A.fe,A.ff,A.eW,A.bx,A.hS,A.bA,A.hU,A.dh,A.fz,A.hW,A.fA,A.eh,A.fK,A.b4,A.d3,A.i8,A.cl,A.fO,A.fP,A.fS,A.fW,A.d4,A.d5,A.ek,A.aO,A.eq,A.ii,A.h0,A.ik,A.h1,A.h2,A.i1,A.iq,A.eu,A.ir,A.iw,A.iz,A.iB,A.et,A.iA,A.is,A.bq,A.ew,A.h9,A.ex,A.ey,A.ev,A.h7,A.ix,A.h8,A.iD,A.ez,A.f8,A.f9,A.dA,A.dz,A.dB,A.fb,A.dg,A.bf,A.aN,A.fH,A.hM,A.aa,A.i4,A.d9])
r(J.fk,[J.fw,J.dN,J.dO,J.d_,J.d0,J.cZ,J.c5])
r(J.dO,[J.bB,J.r,A.c7,A.dY])
r(J.bB,[J.fI,J.dc,J.bi])
s(J.fv,A.el)
s(J.hR,J.r)
r(J.cZ,[J.dM,J.fx])
r(A.T,[A.d1,A.er,A.fB,A.h4,A.fX,A.hb,A.dQ,A.eO,A.bb,A.es,A.h3,A.da,A.eX])
s(A.dd,A.F)
s(A.aJ,A.dd)
r(A.e,[A.dp,A.bs,A.eB,A.cz,A.cA,A.cB,A.cC,A.cD,A.cE,A.cF,A.cG,A.cH,A.cI,A.cJ,A.aS,A.dl,A.bh,A.af,A.c9,A.ca,A.cb,A.cc,A.cd,A.ce,A.cf,A.cg,A.ch,A.ci,A.cj,A.ck,A.G])
r(A.dp,[A.a1,A.dq,A.bj,A.dR])
r(A.a1,[A.eo,A.c6,A.hf])
r(A.cK,[A.dn,A.bX])
r(A.bG,[A.dm,A.eI])
s(A.bU,A.dm)
s(A.e2,A.er)
r(A.bv,[A.eT,A.eU,A.h_,A.jB,A.jD,A.jd,A.je,A.j9,A.j4,A.j5,A.j6,A.j7,A.jf,A.jg,A.jc,A.jj,A.jo,A.jm,A.jn,A.j2,A.hs,A.hz,A.jt,A.ju,A.jv,A.jw,A.jx,A.jy,A.jz,A.i7,A.hO,A.hN])
r(A.h_,[A.fY,A.cy])
r(A.ai,[A.aV,A.he])
s(A.dP,A.aV)
r(A.eU,[A.jC,A.i0,A.i2,A.iQ,A.jh,A.ja,A.jp,A.jl,A.hJ,A.hK,A.hL,A.iC,A.j8])
r(A.dY,[A.dS,A.aj])
r(A.aj,[A.eD,A.eF])
s(A.eE,A.eD)
s(A.bC,A.eE)
s(A.eG,A.eF)
s(A.aM,A.eG)
r(A.bC,[A.dT,A.dU])
r(A.aM,[A.dV,A.dW,A.dX,A.dZ,A.e_,A.c8])
s(A.eJ,A.hb)
s(A.cr,A.eI)
r(A.eT,[A.iX,A.iW,A.jb,A.jk])
r(A.eZ,[A.iS,A.hY,A.hX,A.ip,A.h6])
r(A.bS,[A.f_,A.fC])
s(A.fD,A.dQ)
s(A.iO,A.iP)
r(A.f_,[A.fE,A.h5])
s(A.hZ,A.iS)
r(A.bb,[A.d7,A.fh])
r(A.iJ,[A.db,A.eS,A.hu,A.ap,A.eQ,A.ae,A.ad,A.cL,A.bV,A.aT,A.cM,A.hT,A.d2,A.eg,A.bD,A.bE,A.aY,A.as,A.cn,A.a5,A.aP,A.co,A.df,A.fc,A.f6,A.dL,A.hA])
s(A.j_,A.iG)
s(A.fi,A.fj)
s(A.e4,A.fG)
r(A.aS,[A.eV,A.bT])
s(A.eY,A.dl)
s(A.bw,A.aK)
r(A.a0,[A.bg,A.bZ,A.c3,A.aU,A.c_,A.by,A.c2,A.c0,A.c1,A.cP,A.cN,A.cQ,A.cO])
r(A.hv,[A.eR,A.hy,A.hE,A.hI,A.fy,A.fJ,A.i6,A.i9,A.id,A.ih,A.ij,A.iE])
s(A.hw,A.eR)
s(A.fl,A.be)
r(A.fl,[A.dI,A.fn,A.fo,A.fp,A.dJ])
s(A.fm,A.dt)
s(A.fq,A.dx)
s(A.fd,A.bc)
r(A.bx,[A.bY,A.dC])
s(A.hV,A.hx)
s(A.fr,A.eh)
s(A.fs,A.fK)
s(A.bF,A.J)
r(A.b4,[A.fM,A.fN,A.fQ,A.fR,A.fU,A.fV])
r(A.d3,[A.ej,A.fT])
r(A.fW,[A.d6,A.ar])
s(A.ft,A.ev)
s(A.fu,A.ez)
s(A.dK,A.dg)
r(A.af,[A.cR,A.cS,A.dD,A.dE,A.dF,A.dG,A.cT,A.cU,A.cV,A.cW,A.cX,A.cY])
r(A.aN,[A.e5,A.e6,A.e7,A.e8,A.e9,A.ea,A.eb,A.ec,A.aW])
t(A.dd,A.bp)
t(A.eD,A.F)
t(A.eE,A.ax)
t(A.eF,A.F)
t(A.eG,A.ax)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{h:"int",B:"double",k:"num",C:"String",a3:"bool",e1:"Null",p:"List",H:"Object",a8:"Map",Y:"JSObject"},mangledNames:{},types:["~(aa)","h(h,bo,h)","h([h])","~(h,h,k,k,k)","~(bA,p<h>)","B(@)","~(@,@)","C(@)","~(h,h,h,h,h,aE)","@(@)","~(H?,H?)","@()","a8<C,@>(@)","~(C,aC)","~(h,a3)","a3(p<B>)","h(p<h>{stride!h})","aE(p<B>)","aE(p<h>,h)","h()","@(C)","a3(h)","~(h,a0)","@(@,C)","h(@)","bo(h)","~(h,p<B>)","a3(H?)","a3(C)","h(h,h)","~(h,h)","k(k,k,k,k)","k(k,k,k,k,k)","h(@,@)","aF()","a3(aF)","Y(H,H)","~(k,k,k,k)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti")}
A.oO(v.typeUniverse,JSON.parse('{"bi":"bB","fI":"bB","dc":"bB","r9":"c7","fw":{"a3":[],"M":[]},"dN":{"M":[]},"dO":{"Y":[]},"bB":{"Y":[]},"r":{"p":["1"],"Y":[],"e":["1"],"ah":["1"]},"fv":{"el":[]},"hR":{"r":["1"],"p":["1"],"Y":[],"e":["1"],"ah":["1"]},"bR":{"A":["1"]},"cZ":{"B":[],"k":[],"bd":["k"]},"dM":{"B":[],"h":[],"k":[],"bd":["k"],"M":[]},"fx":{"B":[],"k":[],"bd":["k"],"M":[]},"c5":{"C":[],"bd":["C"],"ly":[],"ah":["@"],"M":[]},"d1":{"T":[]},"aJ":{"F":["h"],"bp":["h"],"p":["h"],"e":["h"],"F.E":"h","bp.E":"h"},"dp":{"e":["1"]},"a1":{"e":["1"]},"eo":{"a1":["1"],"e":["1"],"a1.E":"1","e.E":"1"},"bk":{"A":["1"]},"c6":{"a1":["2"],"e":["2"],"a1.E":"2","e.E":"2"},"bs":{"e":["1"],"e.E":"1"},"eA":{"A":["1"]},"dq":{"e":["1"],"e.E":"1"},"dr":{"A":["1"]},"dd":{"F":["1"],"bp":["1"],"p":["1"],"e":["1"]},"cK":{"a8":["1","2"]},"dn":{"cK":["1","2"],"a8":["1","2"]},"eB":{"e":["1"],"e.E":"1"},"cq":{"A":["1"]},"bX":{"cK":["1","2"],"a8":["1","2"]},"dm":{"bG":["1"],"e":["1"]},"bU":{"dm":["1"],"bG":["1"],"e":["1"]},"e2":{"T":[]},"fB":{"T":[]},"h4":{"T":[]},"bv":{"bW":[]},"eT":{"bW":[]},"eU":{"bW":[]},"h_":{"bW":[]},"fY":{"bW":[]},"cy":{"bW":[]},"fX":{"T":[]},"aV":{"ai":["1","2"],"k2":["1","2"],"a8":["1","2"],"ai.K":"1","ai.V":"2"},"bj":{"e":["1"],"e.E":"1"},"O":{"A":["1"]},"dR":{"e":["1"],"e.E":"1"},"aq":{"A":["1"]},"dP":{"aV":["1","2"],"ai":["1","2"],"k2":["1","2"],"a8":["1","2"],"ai.K":"1","ai.V":"2"},"fZ":{"lv":[]},"iR":{"A":["lv"]},"c7":{"Y":[],"M":[]},"dY":{"Y":[],"a2":[]},"dS":{"Y":[],"a2":[],"M":[]},"aj":{"aL":["1"],"Y":[],"a2":[],"ah":["1"]},"bC":{"F":["B"],"aj":["B"],"p":["B"],"aL":["B"],"Y":[],"a2":[],"ah":["B"],"e":["B"],"ax":["B"]},"aM":{"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"]},"dT":{"bC":[],"hB":[],"F":["B"],"aj":["B"],"p":["B"],"aL":["B"],"Y":[],"a2":[],"ah":["B"],"e":["B"],"ax":["B"],"M":[],"F.E":"B"},"dU":{"bC":[],"jS":[],"F":["B"],"aj":["B"],"p":["B"],"aL":["B"],"Y":[],"a2":[],"ah":["B"],"e":["B"],"ax":["B"],"M":[],"F.E":"B"},"dV":{"aM":[],"hQ":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"dW":{"aM":[],"dH":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"dX":{"aM":[],"jX":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"dZ":{"aM":[],"kn":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"e_":{"aM":[],"bo":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"c8":{"aM":[],"aE":[],"F":["h"],"aj":["h"],"p":["h"],"aL":["h"],"Y":[],"a2":[],"ah":["h"],"e":["h"],"ax":["h"],"M":[],"F.E":"h"},"hb":{"T":[]},"eJ":{"T":[]},"cr":{"bG":["1"],"e":["1"]},"eC":{"A":["1"]},"F":{"p":["1"],"e":["1"]},"ai":{"a8":["1","2"]},"bG":{"e":["1"]},"eI":{"bG":["1"],"e":["1"]},"he":{"ai":["C","@"],"a8":["C","@"],"ai.K":"C","ai.V":"@"},"hf":{"a1":["C"],"e":["C"],"a1.E":"C","e.E":"C"},"f_":{"bS":["C","p<h>"]},"dQ":{"T":[]},"fD":{"T":[]},"fC":{"bS":["H?","C"]},"fE":{"bS":["C","p<h>"]},"h5":{"bS":["C","p<h>"]},"B":{"k":[],"bd":["k"]},"h":{"k":[],"bd":["k"]},"p":{"e":["1"]},"k":{"bd":["k"]},"C":{"bd":["C"],"ly":[]},"eO":{"T":[]},"er":{"T":[]},"bb":{"T":[]},"d7":{"T":[]},"fh":{"T":[]},"es":{"T":[]},"h3":{"T":[]},"da":{"T":[]},"eX":{"T":[]},"fF":{"T":[]},"em":{"T":[]},"cm":{"nL":[]},"fi":{"fj":[]},"e4":{"fG":[]},"L":{"A":["k"]},"cz":{"y":[],"e":["k"],"e.E":"k"},"cA":{"y":[],"e":["k"],"e.E":"k"},"cB":{"y":[],"e":["k"],"e.E":"k"},"cC":{"y":[],"e":["k"],"e.E":"k"},"cD":{"y":[],"e":["k"],"e.E":"k"},"cE":{"y":[],"e":["k"],"e.E":"k"},"cF":{"y":[],"e":["k"],"e.E":"k"},"cG":{"y":[],"e":["k"],"e.E":"k"},"cH":{"y":[],"e":["k"],"e.E":"k"},"cI":{"y":[],"e":["k"],"e.E":"k"},"cJ":{"y":[],"e":["k"],"e.E":"k"},"aS":{"y":[],"e":["k"],"e.E":"k"},"eV":{"y":[],"e":["k"],"e.E":"k"},"bT":{"y":[],"e":["k"],"e.E":"k"},"dl":{"y":[],"e":["k"],"e.E":"k"},"eY":{"y":[],"e":["k"],"e.E":"k"},"bw":{"aK":[]},"bg":{"a0":[]},"bZ":{"a0":[]},"c3":{"a0":[]},"aU":{"a0":[]},"c_":{"a0":[]},"by":{"a0":[]},"c2":{"a0":[]},"c0":{"a0":[]},"c1":{"a0":[]},"cP":{"a0":[]},"cN":{"a0":[]},"cQ":{"a0":[]},"cO":{"a0":[]},"bc":{"J":[]},"dI":{"be":[]},"fl":{"be":[]},"f5":{"J":[]},"fm":{"dt":[]},"fn":{"be":[]},"fo":{"be":[]},"fp":{"be":[]},"dJ":{"be":[]},"fq":{"dx":[]},"dy":{"J":[]},"fe":{"J":[]},"fd":{"bc":[],"J":[]},"bY":{"bx":[]},"dC":{"bx":[]},"fr":{"eh":[]},"fK":{"J":[]},"fs":{"J":[]},"bF":{"J":[]},"fM":{"b4":[]},"fN":{"b4":[]},"fQ":{"b4":[]},"fR":{"b4":[]},"fU":{"b4":[]},"fV":{"b4":[]},"ej":{"d3":[]},"fT":{"d3":[]},"fO":{"J":[]},"d4":{"J":[]},"d5":{"J":[]},"ek":{"J":[]},"eq":{"J":[]},"h2":{"J":[]},"fu":{"ez":[]},"dg":{"J":[]},"dK":{"dg":[],"J":[]},"bh":{"e":["t"],"e.E":"t"},"af":{"e":["t"]},"cR":{"af":[],"e":["t"],"e.E":"t"},"cS":{"af":[],"e":["t"],"e.E":"t"},"dD":{"af":[],"e":["t"],"e.E":"t"},"dE":{"af":[],"e":["t"],"e.E":"t"},"dF":{"af":[],"e":["t"],"e.E":"t"},"dG":{"af":[],"e":["t"],"e.E":"t"},"cT":{"af":[],"e":["t"],"e.E":"t"},"cU":{"af":[],"e":["t"],"e.E":"t"},"cV":{"af":[],"e":["t"],"e.E":"t"},"cW":{"af":[],"e":["t"],"e.E":"t"},"cX":{"af":[],"e":["t"],"e.E":"t"},"cY":{"af":[],"e":["t"],"e.E":"t"},"e5":{"aN":[]},"e6":{"aN":[]},"e7":{"aN":[]},"e8":{"aN":[]},"e9":{"aN":[]},"ea":{"aN":[]},"eb":{"aN":[]},"ec":{"aN":[]},"aW":{"aN":[]},"c9":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"ca":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"cb":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"cc":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"cd":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"ce":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"fH":{"A":["t"]},"cf":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"cg":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"ch":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"ci":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"cj":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"ck":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"G":{"t":[],"y":[],"e":["k"],"A":["t"],"e.E":"k"},"mV":{"a2":[]},"jX":{"p":["h"],"a2":[],"e":["h"]},"aE":{"p":["h"],"a2":[],"e":["h"]},"hQ":{"p":["h"],"a2":[],"e":["h"]},"kn":{"p":["h"],"a2":[],"e":["h"]},"dH":{"p":["h"],"a2":[],"e":["h"]},"bo":{"p":["h"],"a2":[],"e":["h"]},"hB":{"p":["B"],"a2":[],"e":["B"]},"jS":{"p":["B"],"a2":[],"e":["B"]},"t":{"y":[],"A":["t"],"e":["k"]}}'))
A.oN(v.typeUniverse,JSON.parse('{"dp":1,"dd":1,"aj":1,"eI":1,"eZ":2,"fW":1}'))
var u=(function rtii(){var t=A.Z
return{G:t("y"),W:t("bd<@>"),O:t("bU<C>"),bU:t("T"),aX:t("f2"),gV:t("f4"),h4:t("hB"),Z:t("bW"),ct:t("dz"),gj:t("f8"),ak:t("f9"),fa:t("dA"),gx:t("ff"),P:t("aC"),r:t("a0"),v:t("af"),an:t("dH"),bM:t("e<B>"),hf:t("e<@>"),hb:t("e<h>"),eB:t("r<eW>"),g9:t("r<f3>"),dw:t("r<dt>"),w:t("r<dx>"),F:t("r<dz>"),g:t("r<bh>"),b7:t("r<bA>"),Q:t("r<p<p<p<h>>>>"),o:t("r<p<p<h>>>"),gy:t("r<p<B>>"),S:t("r<p<h>>"),ez:t("r<a8<C,H>>"),c7:t("r<a8<C,@>>"),a4:t("r<a8<C,h>>"),b8:t("r<a8<C,p<h>>>"),dm:t("r<eh>"),_:t("r<cl>"),af:t("r<b4>"),l:t("r<fS>"),s:t("r<C>"),aU:t("r<h1>"),h:t("r<aE>"),ao:t("r<bq>"),R:t("r<h8>"),J:t("r<ez>"),g5:t("r<ha>"),gn:t("r<hc>"),e8:t("r<dh>"),cE:t("r<aF>"),n:t("r<B>"),b:t("r<@>"),t:t("r<h>"),f8:t("r<fz?>"),ca:t("r<p<h>?>"),hh:t("r<bo?>"),ff:t("r<aE?>"),A:t("r<~(aa)>"),aP:t("ah<@>"),u:t("dN"),m:t("Y"),U:t("bi"),eA:t("aL<@>"),d2:t("bA"),f0:t("p<dH>"),fv:t("p<p<dH>>"),gS:t("p<p<bq>>"),x:t("p<cl>"),B:t("p<et>"),e6:t("p<bq>"),eQ:t("p<ew>"),db:t("p<ex>"),cC:t("p<ey>"),H:t("p<B>"),j:t("p<@>"),L:t("p<h>"),C:t("p<bx?>"),d:t("p<p<h>?>"),ge:t("p<bq?>"),gR:t("p<eH?>"),cP:t("p<h?>"),ck:t("a8<C,C>"),c:t("a8<C,@>"),f:t("a8<@,@>"),d4:t("bC"),bc:t("aM"),e:t("c8"),a:t("e1"),K:t("H"),dv:t("t"),fW:t("cl"),fh:t("fP"),g0:t("ej"),ha:t("d3"),fi:t("d4"),k:t("d9"),gT:t("rb"),N:t("C"),cV:t("h0"),ci:t("M"),bv:t("bo"),D:t("aE"),bI:t("dc"),dd:t("et"),ai:t("ew"),gU:t("ex"),dE:t("ey"),cc:t("bs<C>"),eK:t("bs<aF>"),E:t("aF"),eO:t("eH"),y:t("a3"),bB:t("a3(C)"),fJ:t("a3(aF)"),i:t("B"),z:t("@"),p:t("h"),eH:t("l3<e1>?"),fe:t("bx?"),bC:t("hQ?"),bX:t("Y?"),M:t("p<@>?"),T:t("p<h>?"),eC:t("p<bx?>?"),fl:t("p<p<h>?>?"),di:t("p<h?>?"),cZ:t("a8<C,C>?"),Y:t("a8<@,@>?"),X:t("H?"),dk:t("C?"),aD:t("aE?"),eW:t("eu?"),aj:t("bq?"),dP:t("h9?"),br:t("hg?"),fQ:t("a3?"),cD:t("B?"),I:t("h?"),cg:t("k?"),e7:t("~(h,a3)?"),q:t("k"),V:t("~(bA,p<h>)"),cA:t("~(C,@)"),d6:t("~(h,a3)"),dX:t("~(k,k,k,k)")}})();(function constants(){var t=hunkHelpers.makeConstList
B.d6=J.fk.prototype
B.c=J.r.prototype
B.a=J.dM.prototype
B.b=J.cZ.prototype
B.p=J.c5.prototype
B.d8=J.bi.prototype
B.d9=J.dO.prototype
B.W=A.dS.prototype
B.ai=A.dT.prototype
B.aj=A.dU.prototype
B.aA=A.dV.prototype
B.X=A.dW.prototype
B.aB=A.dX.prototype
B.Y=A.dZ.prototype
B.o=A.e_.prototype
B.e=A.c8.prototype
B.bU=J.fI.prototype
B.aJ=J.dc.prototype
B.a2=new A.eQ(0,"direct")
B.am=new A.eQ(1,"alpha")
B.aL=new A.ad(0,"none")
B.an=new A.ad(3,"bitfields")
B.ao=new A.ad(6,"alphaBitfields")
B.ap=new A.eS(0,"littleEndian")
B.aM=new A.eS(1,"bigEndian")
B.cs=new A.dr(A.Z("dr<0&>"))
B.aN=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.ct=function() {
  var toStringFunction = Object.prototype.toString;
  function getTag(o) {
    var s = toStringFunction.call(o);
    return s.substring(8, s.length - 1);
  }
  function getUnknownTag(object, tag) {
    if (/^HTML[A-Z].*Element$/.test(tag)) {
      var name = toStringFunction.call(object);
      if (name == "[object Object]") return null;
      return "HTMLElement";
    }
  }
  function getUnknownTagGenericBrowser(object, tag) {
    if (object instanceof HTMLElement) return "HTMLElement";
    return getUnknownTag(object, tag);
  }
  function prototypeForTag(tag) {
    if (typeof window == "undefined") return null;
    if (typeof window[tag] == "undefined") return null;
    var constructor = window[tag];
    if (typeof constructor != "function") return null;
    return constructor.prototype;
  }
  function discriminator(tag) { return null; }
  var isBrowser = typeof HTMLElement == "function";
  return {
    getTag: getTag,
    getUnknownTag: isBrowser ? getUnknownTagGenericBrowser : getUnknownTag,
    prototypeForTag: prototypeForTag,
    discriminator: discriminator };
}
B.cy=function(getTagFallback) {
  return function(hooks) {
    if (typeof navigator != "object") return hooks;
    var userAgent = navigator.userAgent;
    if (typeof userAgent != "string") return hooks;
    if (userAgent.indexOf("DumpRenderTree") >= 0) return hooks;
    if (userAgent.indexOf("Chrome") >= 0) {
      function confirm(p) {
        return typeof window == "object" && window[p] && window[p].name == p;
      }
      if (confirm("Window") && confirm("HTMLElement")) return hooks;
    }
    hooks.getTag = getTagFallback;
  };
}
B.cu=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.cx=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Firefox") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "GeoGeolocation": "Geolocation",
    "Location": "!Location",
    "WorkerMessageEvent": "MessageEvent",
    "XMLDocument": "!Document"};
  function getTagFirefox(o) {
    var tag = getTag(o);
    return quickMap[tag] || tag;
  }
  hooks.getTag = getTagFirefox;
}
B.cw=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Trident/") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "HTMLDDElement": "HTMLElement",
    "HTMLDTElement": "HTMLElement",
    "HTMLPhraseElement": "HTMLElement",
    "Position": "Geoposition"
  };
  function getTagIE(o) {
    var tag = getTag(o);
    var newTag = quickMap[tag];
    if (newTag) return newTag;
    if (tag == "Object") {
      if (window.DataView && (o instanceof window.DataView)) return "DataView";
    }
    return tag;
  }
  function prototypeForTagIE(tag) {
    var constructor = window[tag];
    if (constructor == null) return null;
    return constructor.prototype;
  }
  hooks.getTag = getTagIE;
  hooks.prototypeForTag = prototypeForTagIE;
}
B.cv=function(hooks) {
  var getTag = hooks.getTag;
  var prototypeForTag = hooks.prototypeForTag;
  function getTagFixed(o) {
    var tag = getTag(o);
    if (tag == "Document") {
      if (!!o.xmlVersion) return "!Document";
      return "!HTMLDocument";
    }
    return tag;
  }
  function prototypeForTagFixed(tag) {
    if (tag == "Document") return null;
    return prototypeForTag(tag);
  }
  hooks.getTag = getTagFixed;
  hooks.prototypeForTag = prototypeForTagFixed;
}
B.aO=function(hooks) { return hooks; }

B.K=new A.fC()
B.aP=new A.fE()
B.cz=new A.fF()
B.a3=new A.ie()
B.aQ=new A.h5()
B.cA=new A.ip()
B.B=new A.iF()
B.cB=new A.j_()
B.aR=new A.hu(4,"luminance")
B.cC=new A.eY(4294967295)
B.cD=new A.bV(0,"red")
B.cE=new A.bV(1,"green")
B.cF=new A.bV(2,"blue")
B.cG=new A.bV(3,"alpha")
B.cH=new A.bV(4,"other")
B.aS=new A.cL(0,"uint")
B.aq=new A.cL(1,"half")
B.ar=new A.cL(2,"float")
B.aT=new A.aT(0,"none")
B.cP=new A.hA(2,"both")
B.w=new A.ap(0,"uint1")
B.y=new A.ap(1,"uint2")
B.H=new A.ap(10,"float32")
B.L=new A.ap(11,"float64")
B.z=new A.ap(2,"uint4")
B.f=new A.ap(3,"uint8")
B.l=new A.ap(4,"uint16")
B.I=new A.ap(5,"uint32")
B.M=new A.ap(6,"int8")
B.N=new A.ap(7,"int16")
B.O=new A.ap(8,"int32")
B.C=new A.ap(9,"float16")
B.aU=new A.f6(1,"page")
B.j=new A.f6(2,"sequence")
B.cQ=new A.a7("an index points past the end of the vertex list \u2014 the file is corrupt")
B.cR=new A.a7("no JSON chunk in the GLB")
B.cS=new A.a7("KTX2/Basis textures are not approved and cannot be decoded here \u2014 re-export with plain PNG or JPEG textures (guide \xa7C8)")
B.cT=new A.a7("the GLB header length does not match the file \u2014 it was edited after export")
B.aV=new A.a7("the long axis of this mesh runs along X, so --toe +z/-z cannot apply \u2014 say --toe +x or --toe -x")
B.cU=new A.a7("the mesh is taller than it is long, so its up axis is not +Y \u2014 this is what a Z-up scene looks like when the exporter's rotation was baked the wrong way. Open it, apply rotations (Ctrl+A \u2192 Rotation) and re-export with Transform \u2192 +Y Up ON (guide \xa7C8)")
B.cV=new A.a7('not a GLB: the first four bytes are not "glTF" \u2014 export "glTF Binary (.glb)"')
B.cW=new A.a7("glTF version is not 2")
B.cX=new A.a7("the file is too short to be a GLB")
B.cY=new A.a7("the scene instances the mesh more than once at different transforms \u2014 apply the transforms and delete the extra copies before handover (guide \xa7C3)")
B.cZ=new A.a7("a primitive has no POSITION attribute \u2014 there is nothing to normalise")
B.d_=new A.a7("a GLB chunk runs past the end of the file")
B.d0=new A.a7("the mesh has no length along Z")
B.d1=new A.a7("the file contains no triangles")
B.d2=new A.a7("the JSON chunk is not an object")
B.P=new A.fc(0,"none")
B.d3=new A.fc(1,"deflate")
B.aW=new A.cM(2,"cur")
B.d=new A.ae(0,"none")
B.aX=new A.ae(1,"byte")
B.aY=new A.ae(10,"sRational")
B.aZ=new A.ae(11,"single")
B.b_=new A.ae(12,"double")
B.b0=new A.ae(13,"ifd")
B.k=new A.ae(2,"ascii")
B.i=new A.ae(3,"short")
B.n=new A.ae(4,"long")
B.r=new A.ae(5,"rational")
B.b1=new A.ae(6,"sByte")
B.D=new A.ae(7,"undefined")
B.b2=new A.ae(8,"sShort")
B.b3=new A.ae(9,"sLong")
B.as=new A.dL(0,"nearest")
B.d7=new A.dL(1,"linear")
B.b4=new A.dL(3,"average")
B.b5=new A.hT(0,"yuv444")
B.da=new A.hX(null)
B.db=new A.hY(null)
B.dc=new A.hZ(!1)
B.dd=t([0,0,0],u.n)
B.de=t([0,0,0,1],u.n)
B.a4=t([0,2,8],u.t)
B.di=t([0,4,2,1],u.t)
B.d4=new A.cM(0,"invalid")
B.d5=new A.cM(1,"ico")
B.dl=t([B.d4,B.d5,B.aW],A.Z("r<cM>"))
B.dA=t([1,1,1],u.n)
B.b7=t([252,243,207,63],u.t)
B.k_=new A.d2(0,"none")
B.bX=new A.d2(1,"background")
B.bY=new A.d2(2,"previous")
B.b8=t([B.k_,B.bX,B.bY],A.Z("r<d2>"))
B.a5=t([292,260,226,226],u.t)
B.b9=t([0,0,2,1,3,3,2,4,3,5,5,4,4,0,0,1,125],u.t)
B.ba=t([2,3,7],u.t)
B.a6=t([3226,6412,200,168,38,38,134,134,100,100,100,100,68,68,68,68],u.t)
B.dP=t([3,3,11],u.t)
B.ay=t([128,128,128,128,128,128,128,128,128,128,128],u.t)
B.bf=t([B.ay,B.ay,B.ay],u.S)
B.ez=t([253,136,254,255,228,219,128,128,128,128,128],u.t)
B.fw=t([189,129,242,255,227,213,255,219,128,128,128],u.t)
B.fB=t([106,126,227,252,214,209,255,255,128,128,128],u.t)
B.hY=t([B.ez,B.fw,B.fB],u.S)
B.i4=t([1,98,248,255,236,226,255,255,128,128,128],u.t)
B.dV=t([181,133,238,254,221,234,255,154,128,128,128],u.t)
B.dT=t([78,134,202,247,198,180,255,219,128,128,128],u.t)
B.iu=t([B.i4,B.dV,B.dT],u.S)
B.eu=t([1,185,249,255,243,255,128,128,128,128,128],u.t)
B.i1=t([184,150,247,255,236,224,128,128,128,128,128],u.t)
B.jk=t([77,110,216,255,236,230,128,128,128,128,128],u.t)
B.hu=t([B.eu,B.i1,B.jk],u.S)
B.hC=t([1,101,251,255,241,255,128,128,128,128,128],u.t)
B.ex=t([170,139,241,252,236,209,255,255,128,128,128],u.t)
B.hI=t([37,116,196,243,228,255,255,255,128,128,128],u.t)
B.eg=t([B.hC,B.ex,B.hI],u.S)
B.fN=t([1,204,254,255,245,255,128,128,128,128,128],u.t)
B.jz=t([207,160,250,255,238,128,128,128,128,128,128],u.t)
B.jy=t([102,103,231,255,211,171,128,128,128,128,128],u.t)
B.eV=t([B.fN,B.jz,B.jy],u.S)
B.e9=t([1,152,252,255,240,255,128,128,128,128,128],u.t)
B.jE=t([177,135,243,255,234,225,128,128,128,128,128],u.t)
B.hp=t([80,129,211,255,194,224,128,128,128,128,128],u.t)
B.hX=t([B.e9,B.jE,B.hp],u.S)
B.bk=t([1,1,255,128,128,128,128,128,128,128,128],u.t)
B.ik=t([246,1,255,128,128,128,128,128,128,128,128],u.t)
B.h9=t([255,128,128,128,128,128,128,128,128,128,128],u.t)
B.jO=t([B.bk,B.ik,B.h9],u.S)
B.eP=t([B.bf,B.hY,B.iu,B.hu,B.eg,B.eV,B.hX,B.jO],u.o)
B.jm=t([198,35,237,223,193,187,162,160,145,155,62],u.t)
B.ey=t([131,45,198,221,172,176,220,157,252,221,1],u.t)
B.jl=t([68,47,146,208,149,167,221,162,255,223,128],u.t)
B.fW=t([B.jm,B.ey,B.jl],u.S)
B.iv=t([1,149,241,255,221,224,255,255,128,128,128],u.t)
B.iL=t([184,141,234,253,222,220,255,199,128,128,128],u.t)
B.h5=t([81,99,181,242,176,190,249,202,255,255,128],u.t)
B.j8=t([B.iv,B.iL,B.h5],u.S)
B.j_=t([1,129,232,253,214,197,242,196,255,255,128],u.t)
B.jw=t([99,121,210,250,201,198,255,202,128,128,128],u.t)
B.hZ=t([23,91,163,242,170,187,247,210,255,255,128],u.t)
B.hb=t([B.j_,B.jw,B.hZ],u.S)
B.fa=t([1,200,246,255,234,255,128,128,128,128,128],u.t)
B.iW=t([109,178,241,255,231,245,255,255,128,128,128],u.t)
B.dF=t([44,130,201,253,205,192,255,255,128,128,128],u.t)
B.jd=t([B.fa,B.iW,B.dF],u.S)
B.e3=t([1,132,239,251,219,209,255,165,128,128,128],u.t)
B.dm=t([94,136,225,251,218,190,255,255,128,128,128],u.t)
B.j1=t([22,100,174,245,186,161,255,199,128,128,128],u.t)
B.hA=t([B.e3,B.dm,B.j1],u.S)
B.iK=t([1,182,249,255,232,235,128,128,128,128,128],u.t)
B.hR=t([124,143,241,255,227,234,128,128,128,128,128],u.t)
B.ft=t([35,77,181,251,193,211,255,205,128,128,128],u.t)
B.fD=t([B.iK,B.hR,B.ft],u.S)
B.jP=t([1,157,247,255,236,231,255,255,128,128,128],u.t)
B.eO=t([121,141,235,255,225,227,255,255,128,128,128],u.t)
B.iY=t([45,99,188,251,195,217,255,224,128,128,128],u.t)
B.ef=t([B.jP,B.eO,B.iY],u.S)
B.dn=t([1,1,251,255,213,255,128,128,128,128,128],u.t)
B.dJ=t([203,1,248,255,255,128,128,128,128,128,128],u.t)
B.iM=t([137,1,177,255,224,255,128,128,128,128,128],u.t)
B.ea=t([B.dn,B.dJ,B.iM],u.S)
B.iD=t([B.fW,B.j8,B.hb,B.jd,B.hA,B.fD,B.ef,B.ea],u.o)
B.eZ=t([253,9,248,251,207,208,255,192,128,128,128],u.t)
B.il=t([175,13,224,243,193,185,249,198,255,255,128],u.t)
B.jN=t([73,17,171,221,161,179,236,167,255,234,128],u.t)
B.ic=t([B.eZ,B.il,B.jN],u.S)
B.iz=t([1,95,247,253,212,183,255,255,128,128,128],u.t)
B.hi=t([239,90,244,250,211,209,255,255,128,128,128],u.t)
B.jj=t([155,77,195,248,188,195,255,255,128,128,128],u.t)
B.iJ=t([B.iz,B.hi,B.jj],u.S)
B.fP=t([1,24,239,251,218,219,255,205,128,128,128],u.t)
B.ip=t([201,51,219,255,196,186,128,128,128,128,128],u.t)
B.hh=t([69,46,190,239,201,218,255,228,128,128,128],u.t)
B.ix=t([B.fP,B.ip,B.hh],u.S)
B.fz=t([1,191,251,255,255,128,128,128,128,128,128],u.t)
B.hG=t([223,165,249,255,213,255,128,128,128,128,128],u.t)
B.i3=t([141,124,248,255,255,128,128,128,128,128,128],u.t)
B.iZ=t([B.fz,B.hG,B.i3],u.S)
B.fY=t([1,16,248,255,255,128,128,128,128,128,128],u.t)
B.eM=t([190,36,230,255,236,255,128,128,128,128,128],u.t)
B.eA=t([149,1,255,128,128,128,128,128,128,128,128],u.t)
B.e4=t([B.fY,B.eM,B.eA],u.S)
B.i0=t([1,226,255,128,128,128,128,128,128,128,128],u.t)
B.ig=t([247,192,255,128,128,128,128,128,128,128,128],u.t)
B.ji=t([240,128,255,128,128,128,128,128,128,128,128],u.t)
B.dL=t([B.i0,B.ig,B.ji],u.S)
B.jc=t([1,134,252,255,255,128,128,128,128,128,128],u.t)
B.hQ=t([213,62,250,255,255,128,128,128,128,128,128],u.t)
B.jC=t([55,93,255,128,128,128,128,128,128,128,128],u.t)
B.i_=t([B.jc,B.hQ,B.jC],u.S)
B.eq=t([B.ic,B.iJ,B.ix,B.iZ,B.e4,B.dL,B.i_,B.bf],u.o)
B.hS=t([202,24,213,235,186,191,220,160,240,175,255],u.t)
B.ew=t([126,38,182,232,169,184,228,174,255,187,128],u.t)
B.e6=t([61,46,138,219,151,178,240,170,255,216,128],u.t)
B.iH=t([B.hS,B.ew,B.e6],u.S)
B.ho=t([1,112,230,250,199,191,247,159,255,255,128],u.t)
B.ee=t([166,109,228,252,211,215,255,174,128,128,128],u.t)
B.hE=t([39,77,162,232,172,180,245,178,255,255,128],u.t)
B.iF=t([B.ho,B.ee,B.hE],u.S)
B.hq=t([1,52,220,246,198,199,249,220,255,255,128],u.t)
B.eT=t([124,74,191,243,183,193,250,221,255,255,128],u.t)
B.fs=t([24,71,130,219,154,170,243,182,255,255,128],u.t)
B.iE=t([B.hq,B.eT,B.fs],u.S)
B.fq=t([1,182,225,249,219,240,255,224,128,128,128],u.t)
B.jB=t([149,150,226,252,216,205,255,171,128,128,128],u.t)
B.jT=t([28,108,170,242,183,194,254,223,255,255,128],u.t)
B.jt=t([B.fq,B.jB,B.jT],u.S)
B.jU=t([1,81,230,252,204,203,255,192,128,128,128],u.t)
B.iT=t([123,102,209,247,188,196,255,233,128,128,128],u.t)
B.jg=t([20,95,153,243,164,173,255,203,128,128,128],u.t)
B.iU=t([B.jU,B.iT,B.jg],u.S)
B.h2=t([1,222,248,255,216,213,128,128,128,128,128],u.t)
B.hP=t([168,175,246,252,235,205,255,255,128,128,128],u.t)
B.fv=t([47,116,215,255,211,212,255,255,128,128,128],u.t)
B.eH=t([B.h2,B.hP,B.fv],u.S)
B.h1=t([1,121,236,253,212,214,255,255,128,128,128],u.t)
B.hr=t([141,84,213,252,201,202,255,219,128,128,128],u.t)
B.ia=t([42,80,160,240,162,185,255,205,128,128,128],u.t)
B.fF=t([B.h1,B.hr,B.ia],u.S)
B.jI=t([244,1,255,128,128,128,128,128,128,128,128],u.t)
B.dk=t([238,1,255,128,128,128,128,128,128,128,128],u.t)
B.ih=t([B.bk,B.jI,B.dk],u.S)
B.dD=t([B.iH,B.iF,B.iE,B.jt,B.iU,B.eH,B.fF,B.ih],u.o)
B.e5=t([B.eP,B.iD,B.eq,B.dD],u.Q)
B.bc=t([511,1023,2047,4095],u.t)
B.bd=t([63,207,243,252],u.t)
B.en=t([17,18,24,47,99,99,99,99,18,21,26,66,99,99,99,99,24,26,56,99,99,99,99,99,47,66,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99,99],u.t)
B.a7=t([0,1,2,3,4,5,6,7,8,9,10,11],u.t)
B.eC=t([8,8,4,2],u.t)
B.dx=t([173,148,140],u.t)
B.dy=t([176,155,140,135],u.t)
B.dv=t([180,157,141,134,130],u.t)
B.dI=t([254,254,243,230,196,177,153,140,133,130,129],u.t)
B.be=t([B.dx,B.dy,B.dv,B.dI],u.S)
B.bg=t([1,1.387039845,1.306562965,1.175875602,1,0.785694958,0.5411961,0.275899379],u.n)
B.eJ=t([5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5],u.t)
B.bh=t([0,1,3,7,15,31,63,127,255,511,1023,2047,4095],u.t)
B.bi=t([1,2,3,0,4,17,5,18,33,49,65,6,19,81,97,7,34,113,20,50,129,145,161,8,35,66,177,193,21,82,209,240,36,51,98,114,130,9,10,22,23,24,25,26,37,38,39,40,41,42,52,53,54,55,56,57,58,67,68,69,70,71,72,73,74,83,84,85,86,87,88,89,90,99,100,101,102,103,104,105,106,115,116,117,118,119,120,121,122,131,132,133,134,135,136,137,138,146,147,148,149,150,151,152,153,154,162,163,164,165,166,167,168,169,170,178,179,180,181,182,183,184,185,186,194,195,196,197,198,199,200,201,202,210,211,212,213,214,215,216,217,218,225,226,227,228,229,230,231,232,233,234,241,242,243,244,245,246,247,248,249,250],u.t)
B.t=t([0,1,1,2,4,8,1,1,2,4,8,4,8,4],u.t)
B.bj=t([2954,2956,2958,2962,2970,2986,3018,3082,3212,3468,3980,5004],u.t)
B.f0=t(["+x","-x","+y","-y","+z","-z"],u.s)
B.bl=t([280,256,256,256,40],u.t)
B.U=t([0,1,5,6,14,15,27,28,2,4,7,13,16,26,29,42,3,8,12,17,25,30,41,43,9,11,18,24,31,40,44,53,10,19,23,32,39,45,52,54,20,22,33,38,46,51,55,60,21,34,37,47,50,56,59,61,35,36,48,49,57,58,62,63],u.t)
B.a8=t([62,62,30,30,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,3225,588,588,588,588,588,588,588,588,1680,1680,20499,22547,24595,26643,1776,1776,1808,1808,-24557,-22509,-20461,-18413,1904,1904,1936,1936,-16365,-14317,782,782,782,782,814,814,814,814,-12269,-10221,10257,10257,12305,12305,14353,14353,16403,18451,1712,1712,1744,1744,28691,30739,-32749,-30701,-28653,-26605,2061,2061,2061,2061,2061,2061,2061,2061,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,424,750,750,750,750,1616,1616,1648,1648,1424,1424,1456,1456,1488,1488,1520,1520,1840,1840,1872,1872,1968,1968,8209,8209,524,524,524,524,524,524,524,524,556,556,556,556,556,556,556,556,1552,1552,1584,1584,2000,2000,2032,2032,976,976,1008,1008,1040,1040,1072,1072,1296,1296,1328,1328,718,718,718,718,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,456,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,326,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,358,490,490,490,490,490,490,490,490,490,490,490,490,490,490,490,490,4113,4113,6161,6161,848,848,880,880,912,912,944,944,622,622,622,622,654,654,654,654,1104,1104,1136,1136,1168,1168,1200,1200,1232,1232,1264,1264,686,686,686,686,1360,1360,1392,1392,12,12,12,12,12,12,12,12,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390,390],u.t)
B.av=t([4,5,6,7,8,9,10,10,11,12,13,14,15,16,17,17,18,19,20,20,21,21,22,22,23,23,24,25,25,26,27,28,29,30,31,32,33,34,35,36,37,37,38,39,40,41,42,43,44,45,46,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,76,77,78,79,80,81,82,83,84,85,86,87,88,89,91,93,95,96,98,100,101,102,104,106,108,110,112,114,116,118,122,124,126,128,130,132,134,136,138,140,143,145,148,151,154,157],u.t)
B.bm=t([24,7,23,25,40,6,39,41,22,26,38,42,56,5,55,57,21,27,54,58,37,43,72,4,71,73,20,28,53,59,70,74,36,44,88,69,75,52,60,3,87,89,19,29,86,90,35,45,68,76,85,91,51,61,104,2,103,105,18,30,102,106,34,46,84,92,67,77,101,107,50,62,120,1,119,121,83,93,17,31,100,108,66,78,118,122,33,47,117,123,49,63,99,109,82,94,0,116,124,65,79,16,32,98,110,48,115,125,81,95,64,114,126,97,111,80,113,127,96,112],u.t)
B.aw=t([4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,60,62,64,66,68,70,72,74,76,78,80,82,84,86,88,90,92,94,96,98,100,102,104,106,108,110,112,114,116,119,122,125,128,131,134,137,140,143,146,149,152,155,158,161,164,167,170,173,177,181,185,189,193,197,201,205,209,213,217,221,225,229,234,239,245,249,254,259,264,269,274,279,284],u.t)
B.ff=t(["animations","skins","cameras","morphTargets"],u.s)
B.bn=t([0,0,2,1,2,4,4,3,4,7,5,4,4,0,1,2,119],u.t)
B.bo=t([B.aS,B.aq,B.ar],A.Z("r<cL>"))
B.fn=t([0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13],u.t)
B.bp=t([254,253,251,247,239,223,191,127],u.t)
B.ax=t([A.qG(),A.qy(),A.qN(),A.qL(),A.qI(),A.qH(),A.qJ()],u.A)
B.aF=new A.a5(0,"whiteIsZero")
B.ko=new A.a5(1,"blackIsZero")
B.kv=new A.a5(2,"rgb")
B.aH=new A.a5(3,"palette")
B.kw=new A.a5(4,"transparencyMask")
B.cb=new A.a5(5,"cmyk")
B.kx=new A.a5(6,"yCbCr")
B.ky=new A.a5(7,"reserved7")
B.kz=new A.a5(8,"cieLab")
B.kA=new A.a5(9,"iccLab")
B.kp=new A.a5(10,"ituLab")
B.kq=new A.a5(11,"logL")
B.kr=new A.a5(12,"logLuv")
B.ks=new A.a5(13,"colorFilterArray")
B.kt=new A.a5(14,"linearRaw")
B.ku=new A.a5(15,"depth")
B.aG=new A.a5(16,"unknown")
B.br=t([B.aF,B.ko,B.kv,B.aH,B.kw,B.cb,B.kx,B.ky,B.kz,B.kA,B.kp,B.kq,B.kr,B.ks,B.kt,B.ku,B.aG],A.Z("r<a5>"))
B.bt=t([0,0,3,1,1,1,1,1,1,1,1,1,0,0,0,0,0],u.t)
B.bV=new A.eg(0,"source")
B.bW=new A.eg(1,"over")
B.bu=t([B.bV,B.bW],A.Z("r<eg>"))
B.kg=new A.cn(0,"invalid")
B.c9=new A.cn(1,"uint")
B.h=new A.cn(2,"int")
B.a_=new A.cn(3,"float")
B.bv=t([B.kg,B.c9,B.h,B.a_],A.Z("r<cn>"))
B.bw=t([17,18,0,1,2,3,4,5,16,6,7,8,9,10,11,12,13,14,15],u.t)
B.a9=t([-0.0,1,-1,2,-2,3,4,6,-3,5,-4,-5,-6,7,-7,8,-8,-9],u.t)
B.bx=t([B.d,B.aX,B.k,B.i,B.n,B.r,B.b1,B.D,B.b2,B.b3,B.aY,B.aZ,B.b_,B.b0],A.Z("r<ae>"))
B.hg=t([0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15],u.t)
B.cI=new A.aT(1,"rle")
B.cJ=new A.aT(2,"zips")
B.cK=new A.aT(3,"zip")
B.cL=new A.aT(4,"piz")
B.cM=new A.aT(5,"pxr24")
B.cN=new A.aT(6,"b44")
B.cO=new A.aT(7,"b44a")
B.by=t([B.aT,B.cI,B.cJ,B.cK,B.cL,B.cM,B.cN,B.cO],A.Z("r<aT>"))
B.i7=t([231,120,48,89,115,113,120,152,112],u.t)
B.dE=t([152,179,64,126,170,118,46,70,95],u.t)
B.hf=t([175,69,143,80,85,82,72,155,103],u.t)
B.dY=t([56,58,10,171,218,189,17,13,152],u.t)
B.hD=t([114,26,17,163,44,195,21,10,173],u.t)
B.hO=t([121,24,80,195,26,62,44,64,85],u.t)
B.hz=t([144,71,10,38,171,213,144,34,26],u.t)
B.j3=t([170,46,55,19,136,160,33,206,71],u.t)
B.fb=t([63,20,8,114,114,208,12,9,226],u.t)
B.fO=t([81,40,11,96,182,84,29,16,36],u.t)
B.dp=t([B.i7,B.dE,B.hf,B.dY,B.hD,B.hO,B.hz,B.j3,B.fb,B.fO],u.S)
B.eL=t([134,183,89,137,98,101,106,165,148],u.t)
B.iO=t([72,187,100,130,157,111,32,75,80],u.t)
B.hV=t([66,102,167,99,74,62,40,234,128],u.t)
B.dK=t([41,53,9,178,241,141,26,8,107],u.t)
B.fK=t([74,43,26,146,73,166,49,23,157],u.t)
B.fk=t([65,38,105,160,51,52,31,115,128],u.t)
B.fo=t([104,79,12,27,217,255,87,17,7],u.t)
B.hd=t([87,68,71,44,114,51,15,186,23],u.t)
B.iG=t([47,41,14,110,182,183,21,17,194],u.t)
B.ij=t([66,45,25,102,197,189,23,18,22],u.t)
B.jh=t([B.eL,B.iO,B.hV,B.dK,B.fK,B.fk,B.fo,B.hd,B.iG,B.ij],u.S)
B.i6=t([88,88,147,150,42,46,45,196,205],u.t)
B.hF=t([43,97,183,117,85,38,35,179,61],u.t)
B.fu=t([39,53,200,87,26,21,43,232,171],u.t)
B.h8=t([56,34,51,104,114,102,29,93,77],u.t)
B.hv=t([39,28,85,171,58,165,90,98,64],u.t)
B.fg=t([34,22,116,206,23,34,43,166,73],u.t)
B.dq=t([107,54,32,26,51,1,81,43,31],u.t)
B.j6=t([68,25,106,22,64,171,36,225,114],u.t)
B.eK=t([34,19,21,102,132,188,16,76,124],u.t)
B.jq=t([62,18,78,95,85,57,50,48,51],u.t)
B.eX=t([B.i6,B.hF,B.fu,B.h8,B.hv,B.fg,B.dq,B.j6,B.eK,B.jq],u.S)
B.hs=t([193,101,35,159,215,111,89,46,111],u.t)
B.ep=t([60,148,31,172,219,228,21,18,111],u.t)
B.e2=t([112,113,77,85,179,255,38,120,114],u.t)
B.jn=t([40,42,1,196,245,209,10,25,109],u.t)
B.h_=t([88,43,29,140,166,213,37,43,154],u.t)
B.fi=t([61,63,30,155,67,45,68,1,209],u.t)
B.fA=t([100,80,8,43,154,1,51,26,71],u.t)
B.dN=t([142,78,78,16,255,128,34,197,171],u.t)
B.hn=t([41,40,5,102,211,183,4,1,221],u.t)
B.f3=t([51,50,17,168,209,192,23,25,82],u.t)
B.eW=t([B.hs,B.ep,B.e2,B.jn,B.h_,B.fi,B.fA,B.dN,B.hn,B.f3],u.S)
B.fr=t([138,31,36,171,27,166,38,44,229],u.t)
B.eU=t([67,87,58,169,82,115,26,59,179],u.t)
B.it=t([63,59,90,180,59,166,93,73,154],u.t)
B.je=t([40,40,21,116,143,209,34,39,175],u.t)
B.dS=t([47,15,16,183,34,223,49,45,183],u.t)
B.ev=t([46,17,33,183,6,98,15,32,183],u.t)
B.jV=t([57,46,22,24,128,1,54,17,37],u.t)
B.fC=t([65,32,73,115,28,128,23,128,205],u.t)
B.hU=t([40,3,9,115,51,192,18,6,223],u.t)
B.fI=t([87,37,9,115,59,77,64,21,47],u.t)
B.hm=t([B.fr,B.eU,B.it,B.je,B.dS,B.ev,B.jV,B.fC,B.hU,B.fI],u.S)
B.jH=t([104,55,44,218,9,54,53,130,226],u.t)
B.ed=t([64,90,70,205,40,41,23,26,57],u.t)
B.is=t([54,57,112,184,5,41,38,166,213],u.t)
B.fh=t([30,34,26,133,152,116,10,32,134],u.t)
B.id=t([39,19,53,221,26,114,32,73,255],u.t)
B.f1=t([31,9,65,234,2,15,1,118,73],u.t)
B.hl=t([75,32,12,51,192,255,160,43,51],u.t)
B.fj=t([88,31,35,67,102,85,55,186,85],u.t)
B.fT=t([56,21,23,111,59,205,45,37,192],u.t)
B.fU=t([55,38,70,124,73,102,1,34,98],u.t)
B.jL=t([B.jH,B.ed,B.is,B.fh,B.id,B.f1,B.hl,B.fj,B.fT,B.fU],u.S)
B.fS=t([125,98,42,88,104,85,117,175,82],u.t)
B.fm=t([95,84,53,89,128,100,113,101,45],u.t)
B.hJ=t([75,79,123,47,51,128,81,171,1],u.t)
B.eb=t([57,17,5,71,102,57,53,41,49],u.t)
B.io=t([38,33,13,121,57,73,26,1,85],u.t)
B.jA=t([41,10,67,138,77,110,90,47,114],u.t)
B.hj=t([115,21,2,10,102,255,166,23,6],u.t)
B.eN=t([101,29,16,10,85,128,101,196,26],u.t)
B.fy=t([57,18,10,102,102,213,34,20,43],u.t)
B.fZ=t([117,20,15,36,163,128,68,1,26],u.t)
B.hc=t([B.fS,B.fm,B.hJ,B.eb,B.io,B.jA,B.hj,B.eN,B.fy,B.fZ],u.S)
B.fG=t([102,61,71,37,34,53,31,243,192],u.t)
B.jx=t([69,60,71,38,73,119,28,222,37],u.t)
B.fJ=t([68,45,128,34,1,47,11,245,171],u.t)
B.du=t([62,17,19,70,146,85,55,62,70],u.t)
B.jR=t([37,43,37,154,100,163,85,160,1],u.t)
B.ju=t([63,9,92,136,28,64,32,201,85],u.t)
B.iR=t([75,15,9,9,64,255,184,119,16],u.t)
B.eS=t([86,6,28,5,64,255,25,248,1],u.t)
B.ii=t([56,8,17,132,137,255,55,116,128],u.t)
B.e7=t([58,15,20,82,135,57,26,121,40],u.t)
B.hy=t([B.fG,B.jx,B.fJ,B.du,B.jR,B.ju,B.iR,B.eS,B.ii,B.e7],u.S)
B.hM=t([164,50,31,137,154,133,25,35,218],u.t)
B.eR=t([51,103,44,131,131,123,31,6,158],u.t)
B.js=t([86,40,64,135,148,224,45,183,128],u.t)
B.he=t([22,26,17,131,240,154,14,1,209],u.t)
B.es=t([45,16,21,91,64,222,7,1,197],u.t)
B.jf=t([56,21,39,155,60,138,23,102,213],u.t)
B.jK=t([83,12,13,54,192,255,68,47,28],u.t)
B.hW=t([85,26,85,85,128,128,32,146,171],u.t)
B.ha=t([18,11,7,63,144,171,4,4,246],u.t)
B.eY=t([35,27,10,146,174,171,12,26,128],u.t)
B.h3=t([B.hM,B.eR,B.js,B.he,B.es,B.jf,B.jK,B.hW,B.ha,B.eY],u.S)
B.iC=t([190,80,35,99,180,80,126,54,45],u.t)
B.j2=t([85,126,47,87,176,51,41,20,32],u.t)
B.iq=t([101,75,128,139,118,146,116,128,85],u.t)
B.iN=t([56,41,15,176,236,85,37,9,62],u.t)
B.e8=t([71,30,17,119,118,255,17,18,138],u.t)
B.hx=t([101,38,60,138,55,70,43,26,142],u.t)
B.h6=t([146,36,19,30,171,255,97,27,20],u.t)
B.i5=t([138,45,61,62,219,1,81,188,64],u.t)
B.jo=t([32,41,20,117,151,142,20,21,163],u.t)
B.j4=t([112,19,12,61,195,128,48,4,24],u.t)
B.iw=t([B.iC,B.j2,B.iq,B.iN,B.e8,B.hx,B.h6,B.i5,B.jo,B.j4],u.S)
B.bz=t([B.dp,B.jh,B.eX,B.eW,B.hm,B.jL,B.hc,B.hy,B.h3,B.iw],u.o)
B.ak=new A.as(0,"none")
B.F=new A.as(1,"palette")
B.c8=new A.as(2,"rgb")
B.ka=new A.as(3,"gray")
B.kb=new A.as(4,"reserved4")
B.kc=new A.as(5,"reserved5")
B.kd=new A.as(6,"reserved6")
B.ke=new A.as(7,"reserved7")
B.kf=new A.as(8,"reserved8")
B.G=new A.as(9,"paletteRle")
B.c7=new A.as(10,"rgbRle")
B.k9=new A.as(11,"grayRle")
B.bA=t([B.ak,B.F,B.c8,B.ka,B.kb,B.kc,B.kd,B.ke,B.kf,B.G,B.c7,B.k9],A.Z("r<as>"))
B.bB=t([0,1,2,3,17,4,5,33,49,6,18,65,81,7,97,113,19,34,50,129,8,20,66,145,161,177,193,9,35,51,82,240,21,98,114,209,10,22,36,52,225,37,241,23,24,25,26,38,39,40,41,42,53,54,55,56,57,58,67,68,69,70,71,72,73,74,83,84,85,86,87,88,89,90,99,100,101,102,103,104,105,106,115,116,117,118,119,120,121,122,130,131,132,133,134,135,136,137,138,146,147,148,149,150,151,152,153,154,162,163,164,165,166,167,168,169,170,178,179,180,181,182,183,184,185,186,194,195,196,197,198,199,200,201,202,210,211,212,213,214,215,216,217,218,226,227,228,229,230,231,232,233,234,242,243,244,245,246,247,248,249,250],u.t)
B.hH=t([0,1,1,1,0],u.t)
B.bC=t([A.qq(),A.qx(),A.qz(),A.qs(),A.qv(),A.qB(),A.qu(),A.qA(),A.qr(),A.qt()],u.A)
B.au=t([8,0,8,0],u.t)
B.ec=t([5,3,5,3],u.t)
B.dQ=t([3,5,3,5],u.t)
B.b6=t([0,8,0,8],u.t)
B.bb=t([4,4,4,4],u.t)
B.e1=t([4,4,0,0],u.t)
B.bD=t([B.au,B.ec,B.dQ,B.b6,B.au,B.bb,B.e1,B.b6],u.S)
B.aa=t([80,88,23,71,30,30,62,62,4,4,4,4,4,4,4,4,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,11,35,35,35,35,35,35,35,35,35,35,35,35,35,35,35,35,51,51,51,51,51,51,51,51,51,51,51,51,51,51,51,51,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41,41],u.t)
B.i2=t([16,11,10,16,24,40,51,61,12,12,14,19,26,58,60,55,14,13,16,24,40,57,69,56,14,17,22,29,51,87,80,62,18,22,37,56,68,109,103,77,24,35,55,64,81,104,113,92,49,64,78,87,103,121,120,101,72,92,95,98,112,100,103,99],u.t)
B.Q=t([0,1,4,5,16,17,20,21,64,65,68,69,80,81,84,85,256,257,260,261,272,273,276,277,320,321,324,325,336,337,340,341,1024,1025,1028,1029,1040,1041,1044,1045,1088,1089,1092,1093,1104,1105,1108,1109,1280,1281,1284,1285,1296,1297,1300,1301,1344,1345,1348,1349,1360,1361,1364,1365,4096,4097,4100,4101,4112,4113,4116,4117,4160,4161,4164,4165,4176,4177,4180,4181,4352,4353,4356,4357,4368,4369,4372,4373,4416,4417,4420,4421,4432,4433,4436,4437,5120,5121,5124,5125,5136,5137,5140,5141,5184,5185,5188,5189,5200,5201,5204,5205,5376,5377,5380,5381,5392,5393,5396,5397,5440,5441,5444,5445,5456,5457,5460,5461,16384,16385,16388,16389,16400,16401,16404,16405,16448,16449,16452,16453,16464,16465,16468,16469,16640,16641,16644,16645,16656,16657,16660,16661,16704,16705,16708,16709,16720,16721,16724,16725,17408,17409,17412,17413,17424,17425,17428,17429,17472,17473,17476,17477,17488,17489,17492,17493,17664,17665,17668,17669,17680,17681,17684,17685,17728,17729,17732,17733,17744,17745,17748,17749,20480,20481,20484,20485,20496,20497,20500,20501,20544,20545,20548,20549,20560,20561,20564,20565,20736,20737,20740,20741,20752,20753,20756,20757,20800,20801,20804,20805,20816,20817,20820,20821,21504,21505,21508,21509,21520,21521,21524,21525,21568,21569,21572,21573,21584,21585,21588,21589,21760,21761,21764,21765,21776,21777,21780,21781,21824,21825,21828,21829,21840,21841,21844,21845],u.t)
B.bE=t([127,127,191,127,159,191,223,127,143,159,175,191,207,223,239,127,135,143,151,159,167,175,183,191,199,207,215,223,231,239,247,127,131,135,139,143,147,151,155,159,163,167,171,175,179,183,187,191,195,199,203,207,211,215,219,223,227,231,235,239,243,247,251,127,129,131,133,135,137,139,141,143,145,147,149,151,153,155,157,159,161,163,165,167,169,171,173,175,177,179,181,183,185,187,189,191,193,195,197,199,201,203,205,207,209,211,213,215,217,219,221,223,225,227,229,231,233,235,237,239,241,243,245,247,249,251,253,127],u.t)
B.ab=t([7,6,6,5,5,5,5,4,4,4,4,4,4,4,4,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],u.t)
B.E=t([28679,28679,31752,-32759,-31735,-30711,-29687,-28663,29703,29703,30727,30727,-27639,-26615,-25591,-24567],u.t)
B.ac=t([6430,6400,6400,6400,3225,3225,3225,3225,944,944,944,944,976,976,976,976,1456,1456,1456,1456,1488,1488,1488,1488,718,718,718,718,718,718,718,718,750,750,750,750,750,750,750,750,1520,1520,1520,1520,1552,1552,1552,1552,428,428,428,428,428,428,428,428,428,428,428,428,428,428,428,428,654,654,654,654,654,654,654,654,1072,1072,1072,1072,1104,1104,1104,1104,1136,1136,1136,1136,1168,1168,1168,1168,1200,1200,1200,1200,1232,1232,1232,1232,622,622,622,622,622,622,622,622,1008,1008,1008,1008,1040,1040,1040,1040,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,396,396,396,396,396,396,396,396,396,396,396,396,396,396,396,396,1712,1712,1712,1712,1744,1744,1744,1744,846,846,846,846,846,846,846,846,1264,1264,1264,1264,1296,1296,1296,1296,1328,1328,1328,1328,1360,1360,1360,1360,1392,1392,1392,1392,1424,1424,1424,1424,686,686,686,686,686,686,686,686,910,910,910,910,910,910,910,910,1968,1968,1968,1968,2000,2000,2000,2000,2032,2032,2032,2032,16,16,16,16,10257,10257,10257,10257,12305,12305,12305,12305,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,330,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,362,878,878,878,878,878,878,878,878,1904,1904,1904,1904,1936,1936,1936,1936,-18413,-18413,-16365,-16365,-14317,-14317,-10221,-10221,590,590,590,590,590,590,590,590,782,782,782,782,782,782,782,782,1584,1584,1584,1584,1616,1616,1616,1616,1648,1648,1648,1648,1680,1680,1680,1680,814,814,814,814,814,814,814,814,1776,1776,1776,1776,1808,1808,1808,1808,1840,1840,1840,1840,1872,1872,1872,1872,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,6157,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,-12275,14353,14353,14353,14353,16401,16401,16401,16401,22547,22547,24595,24595,20497,20497,20497,20497,18449,18449,18449,18449,26643,26643,28691,28691,30739,30739,-32749,-32749,-30701,-30701,-28653,-28653,-26605,-26605,-24557,-24557,-22509,-22509,-20461,-20461,8207,8207,8207,8207,8207,8207,8207,8207,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,72,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,104,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,4107,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,266,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,298,524,524,524,524,524,524,524,524,524,524,524,524,524,524,524,524,556,556,556,556,556,556,556,556,556,556,556,556,556,556,556,556,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,136,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,168,460,460,460,460,460,460,460,460,460,460,460,460,460,460,460,460,492,492,492,492,492,492,492,492,492,492,492,492,492,492,492,492,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,2059,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,200,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232,232],u.t)
B.im=t([],u.s)
B.J=t([],u.b)
B.iA=t([0,1,2,3,6,4,5,6,6,6,6,6,6,6,6,7,0],u.t)
B.k0=new A.bD(0,"none")
B.k1=new A.bD(1,"sub")
B.k2=new A.bD(2,"up")
B.k3=new A.bD(3,"average")
B.k4=new A.bD(4,"paeth")
B.ae=t([B.k0,B.k1,B.k2,B.k3,B.k4],A.Z("r<bD>"))
B.A=t([0,1996959894,3993919788,2567524794,124634137,1886057615,3915621685,2657392035,249268274,2044508324,3772115230,2547177864,162941995,2125561021,3887607047,2428444049,498536548,1789927666,4089016648,2227061214,450548861,1843258603,4107580753,2211677639,325883990,1684777152,4251122042,2321926636,335633487,1661365465,4195302755,2366115317,997073096,1281953886,3579855332,2724688242,1006888145,1258607687,3524101629,2768942443,901097722,1119000684,3686517206,2898065728,853044451,1172266101,3705015759,2882616665,651767980,1373503546,3369554304,3218104598,565507253,1454621731,3485111705,3099436303,671266974,1594198024,3322730930,2970347812,795835527,1483230225,3244367275,3060149565,1994146192,31158534,2563907772,4023717930,1907459465,112637215,2680153253,3904427059,2013776290,251722036,2517215374,3775830040,2137656763,141376813,2439277719,3865271297,1802195444,476864866,2238001368,4066508878,1812370925,453092731,2181625025,4111451223,1706088902,314042704,2344532202,4240017532,1658658271,366619977,2362670323,4224994405,1303535960,984961486,2747007092,3569037538,1256170817,1037604311,2765210733,3554079995,1131014506,879679996,2909243462,3663771856,1141124467,855842277,2852801631,3708648649,1342533948,654459306,3188396048,3373015174,1466479909,544179635,3110523913,3462522015,1591671054,702138776,2966460450,3352799412,1504918807,783551873,3082640443,3233442989,3988292384,2596254646,62317068,1957810842,3939845945,2647816111,81470997,1943803523,3814918930,2489596804,225274430,2053790376,3826175755,2466906013,167816743,2097651377,4027552580,2265490386,503444072,1762050814,4150417245,2154129355,426522225,1852507879,4275313526,2312317920,282753626,1742555852,4189708143,2394877945,397917763,1622183637,3604390888,2714866558,953729732,1340076626,3518719985,2797360999,1068828381,1219638859,3624741850,2936675148,906185462,1090812512,3747672003,2825379669,829329135,1181335161,3412177804,3160834842,628085408,1382605366,3423369109,3138078467,570562233,1426400815,3317316542,2998733608,733239954,1555261956,3268935591,3050360625,752459403,1541320221,2607071920,3965973030,1969922972,40735498,2617837225,3943577151,1913087877,83908371,2512341634,3803740692,2075208622,213261112,2463272603,3855990285,2094854071,198958881,2262029012,4057260610,1759359992,534414190,2176718541,4139329115,1873836001,414664567,2282248934,4279200368,1711684554,285281116,2405801727,4167216745,1634467795,376229701,2685067896,3608007406,1308918612,956543938,2808555105,3495958263,1231636301,1047427035,2932959818,3654703836,1088359270,936918e3,2847714899,3736837829,1202900863,817233897,3183342108,3401237130,1404277552,615818150,3134207493,3453421203,1423857449,601450431,3009837614,3294710456,1567103746,711928724,3020668471,3272380065,1510334235,755167117],u.t)
B.x=t([0,1,3,7,15,31,63,127,255],u.t)
B.iS=t([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15],u.t)
B.u=t([255,255,255,255,255,255,255,255,255,255,255],u.t)
B.S=t([B.u,B.u,B.u],u.S)
B.h7=t([176,246,255,255,255,255,255,255,255,255,255],u.t)
B.jD=t([223,241,252,255,255,255,255,255,255,255,255],u.t)
B.eG=t([249,253,253,255,255,255,255,255,255,255,255],u.t)
B.hk=t([B.h7,B.jD,B.eG],u.S)
B.fQ=t([255,244,252,255,255,255,255,255,255,255,255],u.t)
B.fE=t([234,254,254,255,255,255,255,255,255,255,255],u.t)
B.bJ=t([253,255,255,255,255,255,255,255,255,255,255],u.t)
B.eQ=t([B.fQ,B.fE,B.bJ],u.S)
B.jr=t([255,246,254,255,255,255,255,255,255,255,255],u.t)
B.ie=t([239,253,254,255,255,255,255,255,255,255,255],u.t)
B.bF=t([254,255,254,255,255,255,255,255,255,255,255],u.t)
B.iP=t([B.jr,B.ie,B.bF],u.S)
B.bq=t([255,248,254,255,255,255,255,255,255,255,255],u.t)
B.f7=t([251,255,254,255,255,255,255,255,255,255,255],u.t)
B.hN=t([B.bq,B.f7,B.u],u.S)
B.at=t([255,253,254,255,255,255,255,255,255,255,255],u.t)
B.hL=t([251,254,254,255,255,255,255,255,255,255,255],u.t)
B.fe=t([B.at,B.hL,B.bF],u.S)
B.dW=t([255,254,253,255,254,255,255,255,255,255,255],u.t)
B.fM=t([250,255,254,255,254,255,255,255,255,255,255],u.t)
B.ad=t([254,255,255,255,255,255,255,255,255,255,255],u.t)
B.h0=t([B.dW,B.fM,B.ad],u.S)
B.fx=t([B.S,B.hk,B.eQ,B.iP,B.hN,B.fe,B.h0,B.S],u.o)
B.dC=t([217,255,255,255,255,255,255,255,255,255,255],u.t)
B.h4=t([225,252,241,253,255,255,254,255,255,255,255],u.t)
B.ir=t([234,250,241,250,253,255,253,254,255,255,255],u.t)
B.j5=t([B.dC,B.h4,B.ir],u.S)
B.az=t([255,254,255,255,255,255,255,255,255,255,255],u.t)
B.eI=t([223,254,254,255,255,255,255,255,255,255,255],u.t)
B.et=t([238,253,254,254,255,255,255,255,255,255,255],u.t)
B.ib=t([B.az,B.eI,B.et],u.S)
B.fH=t([249,254,255,255,255,255,255,255,255,255,255],u.t)
B.jp=t([B.bq,B.fH,B.u],u.S)
B.j7=t([255,253,255,255,255,255,255,255,255,255,255],u.t)
B.hK=t([247,254,255,255,255,255,255,255,255,255,255],u.t)
B.hB=t([B.j7,B.hK,B.u],u.S)
B.eo=t([252,255,255,255,255,255,255,255,255,255,255],u.t)
B.dM=t([B.at,B.eo,B.u],u.S)
B.bL=t([255,254,254,255,255,255,255,255,255,255,255],u.t)
B.er=t([B.bL,B.bJ,B.u],u.S)
B.i9=t([255,254,253,255,255,255,255,255,255,255,255],u.t)
B.bs=t([250,255,255,255,255,255,255,255,255,255,255],u.t)
B.em=t([B.i9,B.bs,B.ad],u.S)
B.dZ=t([B.j5,B.ib,B.jp,B.hB,B.dM,B.er,B.em,B.S],u.o)
B.iy=t([186,251,250,255,255,255,255,255,255,255,255],u.t)
B.f4=t([234,251,244,254,255,255,255,255,255,255,255],u.t)
B.iQ=t([251,251,243,253,254,255,254,255,255,255,255],u.t)
B.fc=t([B.iy,B.f4,B.iQ],u.S)
B.f9=t([236,253,254,255,255,255,255,255,255,255,255],u.t)
B.i8=t([251,253,253,254,254,255,255,255,255,255,255],u.t)
B.fV=t([B.at,B.f9,B.i8],u.S)
B.iB=t([254,254,254,255,255,255,255,255,255,255,255],u.t)
B.f5=t([B.bL,B.iB,B.u],u.S)
B.iV=t([254,254,255,255,255,255,255,255,255,255,255],u.t)
B.f8=t([B.az,B.iV,B.ad],u.S)
B.bM=t([B.u,B.ad,B.u],u.S)
B.dX=t([B.fc,B.fV,B.f5,B.f8,B.bM,B.S,B.S,B.S],u.o)
B.fL=t([248,255,255,255,255,255,255,255,255,255,255],u.t)
B.fl=t([250,254,252,254,255,255,255,255,255,255,255],u.t)
B.f2=t([248,254,249,253,255,255,255,255,255,255,255],u.t)
B.fX=t([B.fL,B.fl,B.f2],u.S)
B.dU=t([255,253,253,255,255,255,255,255,255,255,255],u.t)
B.jb=t([246,253,253,255,255,255,255,255,255,255,255],u.t)
B.fd=t([252,254,251,254,254,255,255,255,255,255,255],u.t)
B.ja=t([B.dU,B.jb,B.fd],u.S)
B.jQ=t([255,254,252,255,255,255,255,255,255,255,255],u.t)
B.f_=t([248,254,253,255,255,255,255,255,255,255,255],u.t)
B.el=t([253,255,254,254,255,255,255,255,255,255,255],u.t)
B.hT=t([B.jQ,B.f_,B.el],u.S)
B.jJ=t([255,251,254,255,255,255,255,255,255,255,255],u.t)
B.ht=t([245,251,254,255,255,255,255,255,255,255,255],u.t)
B.hw=t([253,253,254,255,255,255,255,255,255,255,255],u.t)
B.eD=t([B.jJ,B.ht,B.hw],u.S)
B.eE=t([255,251,253,255,255,255,255,255,255,255,255],u.t)
B.fR=t([252,253,254,255,255,255,255,255,255,255,255],u.t)
B.iI=t([B.eE,B.fR,B.az],u.S)
B.eh=t([255,252,255,255,255,255,255,255,255,255,255],u.t)
B.jG=t([249,255,254,255,255,255,255,255,255,255,255],u.t)
B.fp=t([255,255,254,255,255,255,255,255,255,255,255],u.t)
B.dt=t([B.eh,B.jG,B.fp],u.S)
B.jS=t([255,255,253,255,255,255,255,255,255,255,255],u.t)
B.f6=t([B.jS,B.bs,B.u],u.S)
B.ek=t([B.fX,B.ja,B.hT,B.eD,B.iI,B.dt,B.f6,B.bM],u.o)
B.j0=t([B.fx,B.dZ,B.dX,B.ek],u.Q)
B.ch=new A.ad(1,"rle8")
B.cm=new A.ad(2,"rle4")
B.cn=new A.ad(4,"jpeg")
B.co=new A.ad(5,"png")
B.cp=new A.ad(7,"reserved7")
B.cq=new A.ad(8,"reserved8")
B.cr=new A.ad(9,"reserved9")
B.ci=new A.ad(10,"reserved10")
B.cj=new A.ad(11,"cmyk")
B.ck=new A.ad(12,"cmykRle8")
B.cl=new A.ad(13,"cmykRle4")
B.af=t([B.aL,B.ch,B.cm,B.an,B.cn,B.co,B.ao,B.cp,B.cq,B.cr,B.ci,B.cj,B.ck,B.cl],A.Z("r<ad>"))
B.R=t([0,128,192,224,240,248,252,254,255],u.t)
B.bG=t([137,80,78,71,13,10,26,10],u.t)
B.V=t([0,1,3,7,15,31,63,127,255,511,1023,2047,4095,8191,16383,32767,65535,131071,262143,524287,1048575,2097151,4194303,8388607,16777215,33554431,67108863,134217727,268435455,536870911,1073741823,2147483647,4294967295],u.t)
B.bH=t([3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258],u.t)
B.dz=t([1,0,0],u.t)
B.iX=t([-1,0,0],u.t)
B.dh=t([0,1,0],u.t)
B.dj=t([0,-1,0],u.t)
B.df=t([0,0,1],u.t)
B.dg=t([0,0,-1],u.t)
B.j9=t([B.dz,B.iX,B.dh,B.dj,B.df,B.dg],u.S)
B.bI=t([1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577],u.t)
B.cf=new A.co(0,"predictor")
B.kO=new A.co(1,"crossColor")
B.kP=new A.co(2,"subtractGreen")
B.cg=new A.co(3,"colorIndexing")
B.bK=t([B.cf,B.kO,B.kP,B.cg],A.Z("r<co>"))
B.v=t([0,17,34,51,68,85,102,119,136,153,170,187,204,221,238,255],u.t)
B.jv=t([73,67,67,95,80,82,79,70,73,76,69,0],u.t)
B.bN=t([A.qC(),A.qw(),A.qM(),A.qK(),A.qE(),A.qD(),A.qF()],u.A)
B.bO=t([0,4,8,12,128,132,136,140,256,260,264,268,384,388,392,396],u.t)
B.bP=t([null,A.r1(),A.r2(),A.r0()],A.Z("r<~(h,h,h,h,h,aE)?>"))
B.ag=t([0,36,72,109,145,182,218,255],u.t)
B.q=t([0,8,16,24,32,41,49,57,65,74,82,90,98,106,115,123,131,139,148,156,164,172,180,189,197,205,213,222,230,238,246,255],u.t)
B.jF=t([8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8],u.t)
B.k5=new A.aY(0,"bitmap")
B.c1=new A.aY(1,"grayscale")
B.k6=new A.aY(2,"indexed")
B.c2=new A.aY(3,"rgb")
B.c3=new A.aY(4,"cmyk")
B.k7=new A.aY(5,"multiChannel")
B.k8=new A.aY(6,"duoTone")
B.c4=new A.aY(7,"lab")
B.bQ=t([B.k5,B.c1,B.k6,B.c2,B.c3,B.k7,B.k8,B.c4],A.Z("r<aY>"))
B.jM=t([0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0],u.t)
B.bR=t([0,0,1,5,1,1,1,1,1,1,0,0,0,0,0,0,0],u.t)
B.ah=t([1,0,0,0,1,0,0,0,1,0,0,0],u.n)
B.dH=t([2,6,2,6],u.t)
B.ei=t([6,2,6,2],u.t)
B.dG=t([2,2,6,6],u.t)
B.dB=t([1,3,3,9],u.t)
B.e_=t([4,0,12,0],u.t)
B.dO=t([3,1,9,3],u.t)
B.eB=t([8,8,0,0],u.t)
B.e0=t([4,12,0,0],u.t)
B.dw=t([16,0,0,0],u.t)
B.ds=t([12,4,0,0],u.t)
B.ej=t([6,6,2,2],u.t)
B.dR=t([3,9,1,3],u.t)
B.dr=t([12,0,4,0],u.t)
B.eF=t([9,3,3,1],u.t)
B.m=t([B.bb,B.dH,B.au,B.ei,B.dG,B.dB,B.e_,B.dO,B.eB,B.e0,B.dw,B.ds,B.ej,B.dR,B.dr,B.eF],u.S)
B.T=t([0,-128,64,-64,32,-96,96,-32,16,-112,80,-48,48,-80,112,-16,8,-120,72,-56,40,-88,104,-24,24,-104,88,-40,56,-72,120,-8,4,-124,68,-60,36,-92,100,-28,20,-108,84,-44,52,-76,116,-12,12,-116,76,-52,44,-84,108,-20,28,-100,92,-36,60,-68,124,-4,2,-126,66,-62,34,-94,98,-30,18,-110,82,-46,50,-78,114,-14,10,-118,74,-54,42,-86,106,-22,26,-102,90,-38,58,-70,122,-6,6,-122,70,-58,38,-90,102,-26,22,-106,86,-42,54,-74,118,-10,14,-114,78,-50,46,-82,110,-18,30,-98,94,-34,62,-66,126,-2,1,-127,65,-63,33,-95,97,-31,17,-111,81,-47,49,-79,113,-15,9,-119,73,-55,41,-87,105,-23,25,-103,89,-39,57,-71,121,-7,5,-123,69,-59,37,-91,101,-27,21,-107,85,-43,53,-75,117,-11,13,-115,77,-51,45,-83,109,-19,29,-99,93,-35,61,-67,125,-3,3,-125,67,-61,35,-93,99,-29,19,-109,83,-45,51,-77,115,-13,11,-117,75,-53,43,-85,107,-21,27,-101,91,-37,59,-69,123,-5,7,-121,71,-57,39,-89,103,-25,23,-105,87,-41,55,-73,119,-9,15,-113,79,-49,47,-81,111,-17,31,-97,95,-33,63,-65,127,-1],u.t)
B.bS=new A.bX([34665,"exif",40965,"interop",34853,"gps"],A.Z("bX<h,C>"))
B.jX={}
B.jW=new A.dn(B.jX,[],A.Z("dn<@,@>"))
B.bT=new A.bX([B.w,1,B.y,3,B.z,15,B.f,255,B.l,65535,B.I,4294967295,B.M,127,B.N,32767,B.O,2147483647,B.C,1,B.H,1,B.L,1],A.Z("bX<ap,h>"))
B.Z=new A.bE(0,"invalid")
B.bZ=new A.bE(1,"pbm")
B.c_=new A.bE(2,"pgm2")
B.aC=new A.bE(3,"pgm5")
B.c0=new A.bE(4,"ppm3")
B.aD=new A.bE(5,"ppm6")
B.jY={KHR_materials_specular:0,KHR_materials_ior:1,KHR_materials_sheen:2,KHR_materials_clearcoat:3,KHR_materials_transmission:4,KHR_materials_volume:5,KHR_materials_iridescence:6,KHR_materials_anisotropy:7,KHR_materials_emissive_strength:8}
B.c5=new A.bU(B.jY,9,u.O)
B.jZ={KHR_draco_mesh_compression:0,EXT_meshopt_compression:1,KHR_texture_basisu:2}
B.c6=new A.bU(B.jZ,3,u.O)
B.aE=new A.aP(0,"bilevel")
B.kh=new A.aP(1,"gray4bit")
B.ki=new A.aP(2,"gray")
B.kj=new A.aP(3,"grayAlpha")
B.kk=new A.aP(4,"palette")
B.ca=new A.aP(5,"rgb")
B.kl=new A.aP(6,"rgba")
B.km=new A.aP(7,"yCbCrSub")
B.a0=new A.aP(8,"generic")
B.kn=new A.aP(9,"invalid")
B.cc=new A.db(0,"plusX")
B.cd=new A.db(1,"minusX")
B.ce=new A.db(2,"plusZ")
B.aI=new A.db(3,"minusZ")
B.kB=A.b8("r3")
B.kC=A.b8("mV")
B.kD=A.b8("hB")
B.kE=A.b8("jS")
B.kF=A.b8("hQ")
B.kG=A.b8("dH")
B.kH=A.b8("jX")
B.kI=A.b8("H")
B.kJ=A.b8("kn")
B.kK=A.b8("bo")
B.kL=A.b8("aE")
B.kM=new A.h6(!1)
B.kN=new A.h6(!0)
B.a1=new A.df(0,"undefined")
B.aK=new A.df(1,"lossy")
B.al=new A.df(2,"lossless")
B.kQ=new A.df(3,"animated")})();(function staticFields(){$.iN=null
$.aH=A.j([],A.Z("r<H>"))
$.lA=null
$.kX=null
$.kW=null
$.mj=null
$.mc=null
$.ml=null
$.js=null
$.jE=null
$.kB=null
$.kv=null
$.lL=!1
$.or=A.j([A.kI(),A.qO(),A.qT(),A.qU(),A.qV(),A.qW(),A.qX(),A.qY(),A.qZ(),A.r_(),A.qP(),A.qQ(),A.qR(),A.qS(),A.kI(),A.kI()],A.Z("r<h(h,bo,h)>"))
$.N=null
$.l2=A.oz()})();(function lazyInitializers(){var t=hunkHelpers.lazyFinal,s=hunkHelpers.lazy
t($,"r5","mo",()=>A.mi("_$dart_dartClosure"))
t($,"r4","kJ",()=>A.mi("_$dart_dartClosure_dartJSInterop"))
t($,"rs","jJ",()=>A.e0(0))
t($,"rK","mI",()=>A.j([new J.fv()],A.Z("r<el>")))
t($,"rc","ms",()=>A.bn(A.im({
toString:function(){return"$receiver$"}})))
t($,"rd","mt",()=>A.bn(A.im({$method$:null,
toString:function(){return"$receiver$"}})))
t($,"re","mu",()=>A.bn(A.im(null)))
t($,"rf","mv",()=>A.bn(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
t($,"ri","my",()=>A.bn(A.im(void 0)))
t($,"rj","mz",()=>A.bn(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
t($,"rh","mx",()=>A.bn(A.lH(null)))
t($,"rg","mw",()=>A.bn(function(){try{null.$method$}catch(r){return r.message}}()))
t($,"rl","mB",()=>A.bn(A.lH(void 0)))
t($,"rk","mA",()=>A.bn(function(){try{(void 0).$method$}catch(r){return r.message}}()))
t($,"rv","mF",()=>A.e0(4096))
t($,"rt","mD",()=>new A.iX().$0())
t($,"ru","mE",()=>new A.iW().$0())
t($,"rJ","hr",()=>A.kE(B.kI))
t($,"r7","mq",()=>A.fa(B.jF))
t($,"r6","mp",()=>A.fa(B.eJ))
t($,"rM","kM",()=>{var r=null,q="ISOSpeed"
return A.aD([11,A.i("ProcessingSoftware",B.k,r),254,A.i("SubfileType",B.n,1),255,A.i("OldSubfileType",B.n,1),256,A.i("ImageWidth",B.n,1),257,A.i("ImageLength",B.n,1),258,A.i("BitsPerSample",B.i,1),259,A.i("Compression",B.i,1),262,A.i("PhotometricInterpretation",B.i,1),263,A.i("Thresholding",B.i,1),264,A.i("CellWidth",B.i,1),265,A.i("CellLength",B.i,1),266,A.i("FillOrder",B.i,1),269,A.i("DocumentName",B.k,r),270,A.i("ImageDescription",B.k,r),271,A.i("Make",B.k,r),272,A.i("Model",B.k,r),273,A.i("StripOffsets",B.n,r),274,A.i("Orientation",B.i,1),277,A.i("SamplesPerPixel",B.i,1),278,A.i("RowsPerStrip",B.n,1),279,A.i("StripByteCounts",B.n,1),280,A.i("MinSampleValue",B.i,1),281,A.i("MaxSampleValue",B.i,1),282,A.i("XResolution",B.r,1),283,A.i("YResolution",B.r,1),284,A.i("PlanarConfiguration",B.i,1),285,A.i("PageName",B.k,r),286,A.i("XPosition",B.r,1),287,A.i("YPosition",B.r,1),290,A.i("GrayResponseUnit",B.i,1),291,A.i("GrayResponseCurve",B.d,r),292,A.i("T4Options",B.d,r),293,A.i("T6Options",B.d,r),296,A.i("ResolutionUnit",B.i,1),297,A.i("PageNumber",B.i,2),300,A.i("ColorResponseUnit",B.d,r),301,A.i("TransferFunction",B.i,768),305,A.i("Software",B.k,r),306,A.i("DateTime",B.k,r),315,A.i("Artist",B.k,r),316,A.i("HostComputer",B.k,r),317,A.i("Predictor",B.i,1),318,A.i("WhitePoint",B.r,2),319,A.i("PrimaryChromaticities",B.r,6),320,A.i("ColorMap",B.i,r),321,A.i("HalftoneHints",B.i,2),322,A.i("TileWidth",B.n,1),323,A.i("TileLength",B.n,1),324,A.i("TileOffsets",B.n,r),325,A.i("TileByteCounts",B.d,r),326,A.i("BadFaxLines",B.d,r),327,A.i("CleanFaxData",B.d,r),328,A.i("ConsecutiveBadFaxLines",B.d,r),332,A.i("InkSet",B.d,r),333,A.i("InkNames",B.d,r),334,A.i("NumberofInks",B.d,r),336,A.i("DotRange",B.d,r),337,A.i("TargetPrinter",B.k,r),338,A.i("ExtraSamples",B.d,r),339,A.i("SampleFormat",B.i,1),340,A.i("SMinSampleValue",B.d,r),341,A.i("SMaxSampleValue",B.d,r),342,A.i("TransferRange",B.d,r),343,A.i("ClipPath",B.d,r),512,A.i("JPEGProc",B.d,r),513,A.i("JPEGInterchangeFormat",B.d,r),514,A.i("JPEGInterchangeFormatLength",B.d,r),529,A.i("YCbCrCoefficients",B.r,3),530,A.i("YCbCrSubSampling",B.i,1),531,A.i("YCbCrPositioning",B.i,1),532,A.i("ReferenceBlackWhite",B.r,6),700,A.i("ApplicationNotes",B.i,1),18246,A.i("Rating",B.i,1),33421,A.i("CFARepeatPatternDim",B.d,r),33422,A.i("CFAPattern",B.d,r),33423,A.i("BatteryLevel",B.d,r),33432,A.i("Copyright",B.k,r),33434,A.i("ExposureTime",B.r,1),33437,A.i("FNumber",B.r,r),33723,A.i("IPTC-NAA",B.n,1),34665,A.i("ExifOffset",B.d,r),34675,A.i("InterColorProfile",B.d,r),34850,A.i("ExposureProgram",B.i,1),34852,A.i("SpectralSensitivity",B.k,r),34853,A.i("GPSOffset",B.d,r),34855,A.i(q,B.n,1),34856,A.i("OECF",B.d,r),34864,A.i("SensitivityType",B.i,1),34866,A.i("RecommendedExposureIndex",B.n,1),34867,A.i(q,B.n,1),36864,A.i("ExifVersion",B.D,r),36867,A.i("DateTimeOriginal",B.k,r),36868,A.i("DateTimeDigitized",B.k,r),36880,A.i("OffsetTime",B.k,r),36881,A.i("OffsetTimeOriginal",B.k,r),36882,A.i("OffsetTimeDigitized",B.k,r),37121,A.i("ComponentsConfiguration",B.D,r),37122,A.i("CompressedBitsPerPixel",B.d,r),37377,A.i("ShutterSpeedValue",B.d,r),37378,A.i("ApertureValue",B.d,r),37379,A.i("BrightnessValue",B.d,r),37380,A.i("ExposureBiasValue",B.d,r),37381,A.i("MaxApertureValue",B.d,r),37382,A.i("SubjectDistance",B.d,r),37383,A.i("MeteringMode",B.d,r),37384,A.i("LightSource",B.d,r),37385,A.i("Flash",B.d,r),37386,A.i("FocalLength",B.d,r),37396,A.i("SubjectArea",B.d,r),37500,A.i("MakerNote",B.D,r),37510,A.i("UserComment",B.D,r),37520,A.i("SubSecTime",B.d,r),37521,A.i("SubSecTimeOriginal",B.d,r),37522,A.i("SubSecTimeDigitized",B.d,r),40091,A.i("XPTitle",B.d,r),40092,A.i("XPComment",B.d,r),40093,A.i("XPAuthor",B.d,r),40094,A.i("XPKeywords",B.d,r),40095,A.i("XPSubject",B.d,r),40960,A.i("FlashPixVersion",B.d,r),40961,A.i("ColorSpace",B.i,1),40962,A.i("ExifImageWidth",B.i,1),40963,A.i("ExifImageLength",B.i,1),40964,A.i("RelatedSoundFile",B.d,r),40965,A.i("InteroperabilityOffset",B.d,r),41483,A.i("FlashEnergy",B.d,r),41484,A.i("SpatialFrequencyResponse",B.d,r),41486,A.i("FocalPlaneXResolution",B.d,r),41487,A.i("FocalPlaneYResolution",B.d,r),41488,A.i("FocalPlaneResolutionUnit",B.d,r),41492,A.i("SubjectLocation",B.d,r),41493,A.i("ExposureIndex",B.d,r),41495,A.i("SensingMethod",B.d,r),41728,A.i("FileSource",B.d,r),41729,A.i("SceneType",B.d,r),41730,A.i("CVAPattern",B.d,r),41985,A.i("CustomRendered",B.d,r),41986,A.i("ExposureMode",B.d,r),41987,A.i("WhiteBalance",B.d,r),41988,A.i("DigitalZoomRatio",B.d,r),41989,A.i("FocalLengthIn35mmFilm",B.d,r),41990,A.i("SceneCaptureType",B.d,r),41991,A.i("GainControl",B.d,r),41992,A.i("Contrast",B.d,r),41993,A.i("Saturation",B.d,r),41994,A.i("Sharpness",B.d,r),41995,A.i("DeviceSettingDescription",B.d,r),41996,A.i("SubjectDistanceRange",B.d,r),42016,A.i("ImageUniqueID",B.d,r),42032,A.i("CameraOwnerName",B.k,r),42033,A.i("BodySerialNumber",B.k,r),42034,A.i("LensSpecification",B.d,r),42035,A.i("LensMake",B.k,r),42036,A.i("LensModel",B.k,r),42037,A.i("LensSerialNumber",B.k,r),42240,A.i("Gamma",B.r,1),50341,A.i("PrintIM",B.d,r),59932,A.i("Padding",B.d,r),59933,A.i("OffsetSchema",B.d,r),65e3,A.i("OwnerName",B.k,r),65001,A.i("SerialNumber",B.k,r)],u.p,A.Z("f1"))})
t($,"r8","ho",()=>A.k4(A.j([0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63,63],u.t)))
s($,"rm","hp",()=>A.e0(511))
s($,"rn","jG",()=>A.e0(511))
s($,"rp","jH",()=>A.lw(2041))
s($,"rq","jI",()=>A.lw(225))
s($,"ro","aB",()=>A.e0(766))
t($,"rN","kN",()=>A.k4(B.iA))
t($,"rO","mJ",()=>A.k4(B.hg))
t($,"rr","mC",()=>A.l_(0,0,0,0))
t($,"ra","mr",()=>A.lg(0,0,0))
t($,"rH","an",()=>A.e0(1))
t($,"rI","av",()=>A.ni(B.e.gB($.an()),0,null))
t($,"rA","am",()=>A.nw(1))
t($,"rB","au",()=>J.mL(B.Y.gB($.am()),0,null))
t($,"rC","K",()=>A.ny(1))
t($,"rE","a4",()=>J.mM(B.o.gB($.K()),0,null))
t($,"rD","bN",()=>A.na(B.o.gB($.K())))
t($,"ry","hq",()=>A.nt(1))
t($,"rz","jK",()=>A.lI(B.X.gB($.hq()),0))
t($,"rw","kK",()=>A.nq(1))
t($,"rx","mG",()=>A.lI(B.ai.gB($.kK()),0))
t($,"rF","kL",()=>A.nN(1))
t($,"rG","mH",()=>{var r=$.kL()
return A.nb(r.gB(r))})})();(function nativeSupport(){!function(){var t=function(a){var n={}
n[a]=1
return Object.keys(hunkHelpers.convertToFastObject(n))[0]}
v.getIsolateTag=function(a){return t("___dart_"+a+v.isolateTag)}
var s="___dart_isolate_tags_"
var r=Object[s]||(Object[s]=Object.create(null))
var q="_ZxYxX"
for(var p=0;;p++){var o=t(q+"_"+p+"_")
if(!(o in r)){r[o]=1
v.isolateTag=o
break}}v.dispatchPropertyName=v.getIsolateTag("dispatch_record")}()
hunkHelpers.setOrUpdateInterceptorsByTag({ArrayBuffer:A.c7,SharedArrayBuffer:A.c7,ArrayBufferView:A.dY,DataView:A.dS,Float32Array:A.dT,Float64Array:A.dU,Int16Array:A.dV,Int32Array:A.dW,Int8Array:A.dX,Uint16Array:A.dZ,Uint32Array:A.e_,Uint8Array:A.c8})
hunkHelpers.setOrUpdateLeafTags({ArrayBuffer:true,SharedArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8Array:false})
A.aj.$nativeSuperclassTag="ArrayBufferView"
A.eD.$nativeSuperclassTag="ArrayBufferView"
A.eE.$nativeSuperclassTag="ArrayBufferView"
A.bC.$nativeSuperclassTag="ArrayBufferView"
A.eF.$nativeSuperclassTag="ArrayBufferView"
A.eG.$nativeSuperclassTag="ArrayBufferView"
A.aM.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$0=function(){return this()}
Function.prototype.$1$1=function(a){return this(a)}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$6=function(a,b,c,d,e,f){return this(a,b,c,d,e,f)}
Function.prototype.$5=function(a,b,c,d,e){return this(a,b,c,d,e)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var t=document.scripts
function onLoad(b){for(var r=0;r<t.length;++r){t[r].removeEventListener("load",onLoad,false)}a(b.target)}for(var s=0;s<t.length;++s){t[s].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var t=A.qg
if(typeof dartMainRunner==="function"){dartMainRunner(t,[])}else{t([])}})})()
// The portal imports this name. `main()` above has already assigned it.
export const soleVisionNormalize = globalThis.soleVisionNormalize
