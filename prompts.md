## go脚本
把文件`check_cookie.go`和`gen_user_cookie.go`的功能合并到一个go脚本中，编译生成可执行文件。并添加以下功能：  
1. 脚本包含两个功能：1. 解析浏览器cookie的；2. 生成新用户；3. 批量生成新用户
2. 功能1：解析浏览器cookie
2.1 从命令行参数获取浏览器cookie字符串、数据库连接字符串（redis[s]://[[username][:password]@][host][:port][/db-number][?option1=value1&option2=value2]）。参数风格使用`--`长参数名，例如`--cookie`、`--redis-dsn`
2.2 解析并验证cookie，输出session ID
2.3 使用session ID从redis获取用户数据，并反序列化输出用户信息
2.4 如果数据库连接字符串为空，则使用内置的默认连接字符串；如果数据库连接失败，则输出redis语句供用户手动执行。参考  
```markdown
# redis使用
# SELECT 0
# GET "credit:session:G422RCRJXYHYPFDYJBTEAEQKLC25WMUFYQHL4MGKKHKWAM7VFGNA"
# 然后把返回的值反序列化输出即可
```
3. 功能2：生成新用户
3.1 从命令行参数获取要生成的用户信息（所有字段均为可选）、数据库连接字符串（postgres://[user[:password]@][netloc][:port][/dbname][?param1=value1&...])，还包含一个api_key的参数用于获取真实id、username, nickname, avatar_url数据（如果没有提供api_key，则使用随机数据生成id, username, nickname，但是avatar_url设为默认https://linux.do/user_avatar/linux.do/diffusion/288/493124_2.png）。
3.2 postgres数据库的插入语句示例如下  
```sql
-- \c linux_do_credit
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO users (
  id, username, nickname, avatar_url, trust_level,
  pay_score, pay_key, sign_key, 
  total_receive, total_payment, total_transfer, total_community, 
  community_balance, available_balance, 
  is_active, is_admin, last_login_at, created_at, updated_at
) VALUES (
  1, 'neo', 'Neo', 'https://linux.do/user_avatar/linux.do/neo/288/12_2.png', random(0,4),
  random(40000,80000), encode(gen_random_bytes(32), 'base64'), encode(gen_random_bytes(32), 'hex'),
  ROUND(random(100,80000),2), ROUND(random(100,50000), 2), ROUND(random(100,50000), 2), ROUND(random(10000,80000), 2),
  ROUND(random(10000,80000),2), ROUND(random(100,80000), 2),
  true, RANDOM()::INT::BOOLEAN, NOW(), NOW(), NOW()
);
```
注意：id（不是自增主键）和username（最重要的）决定唯一性，因此插入时需要确保不重复。
3.3 如果提供了api_key，则使用headers中的User-Api-Key字段调用linuxdo的排行榜API获取真实数据，但是注意可能要cloudflare的反爬虫盾，因此如果获取失败，则回退到随机数据生成。  
使用GET请求`https://linux.do/leaderboard/1?page=1&period=all`，其中`page`参数从1开始递增，每次请求获取100个用户数据，从中任选1个。还需要提示用户当前数据是随机生成的还是从linuxdo获取的真实数据。
返回数据格式如下，然后从返回的数据中提取id, username, nickname, avatar_url字段。avatar_url的格式为`https://linux.do{avatar_template}`，其中`{avatar_template}`字段在返回的数据中提供，需要将其中的`{size}`替换为288。：
```json
{
    "users": [
        {
            "id": 47882,
            "username": "bianselong",
            "name": "变色龙",
            "avatar_template": "/user_avatar/linux.do/bianselong/{size}/130186_2.png",
            "total_score": 36784,
            "position": 101,
            "animated_avatar": null
        },
        {
            "id": 16745,
            "username": "yonse",
            "name": "XYZ",
            "avatar_template": "/user_avatar/linux.do/yonse/{size}/588325_2.png",
            "total_score": 36492,
            "position": 102,
            "animated_avatar": null
        }
    ]
}
```
推荐headers如下：
```json
{
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "Accept-Encoding": "gzip, deflate, br, zstd",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,zh-TW;q=0.7",
    "Cache-Control": "no-cache",
    "User-Api-Key": "<API_KEY>",
    "Discourse-Logged-In": "true",
    "Discourse-Present": "true",
    "Pragma": "no-cache",
    "Referer": "https://linux.do/leaderboard/1",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
}
```
3.4 把生成的用户信息的username、user_id生成redis的session数据，并输出redis的SET语句和浏览器cookie字符串，参考`gen_user_cookie.go`的实现。
3.5 如果数据库连接字符串为空，则使用内置的默认连接字符串；如果数据库连接失败，则输出postgres语句供用户手动执行
4. 功能3：批量生成新用户
4.1 在功能2的基础上，添加一个count参数，表示要生成的用户数量，默认为1。
4.2 循环调用功能2的逻辑，直到生成指定数量的用户。
4.3 如果数据库连接字符串为空，则使用内置的默认连接字符串；如果数据库连接失败，则输出postgres语句供用户手动执行
5. 所有注释和控制台输出使用英文，代码包含良好的异常处理和输入参数验证及提示
6. redis和postgres的go依赖使用`github.com/redis/go-redis/v9`和`github.com/jackc/pgx/v5`包
7. 数据库配置如下：
```yaml
session_cookie_name: "linux_do_credit_session_id"
session_secret: "dev-session-secret"
session_domain: "localhost"
session_age: 86400

database:
  enabled: true
  host: "postgres"
  port: 5432
  username: "postgres_user"
  password: "postgres_pwd"
  database: "linux_do_credit"

redis:
  enabled: true
  addrs:
    - "redis:6379"
  username: ""
  password: "redis_pwd"
  db: 0
  cluster_mode: false
  master_name: ""
  key_prefix: "credit:"
```

文件`check_cookie.go`内容如下：  
```go
package main

import (
	"fmt"
	"github.com/gorilla/securecookie"
	"bytes"
	"encoding/gob"
	"log"
)

func parse_session_value(rawData []byte) {
	// 这是从 Redis 中 GET 到的原始字节流
	// rawData := []byte("\r\x7f\x04\x01\x02\xff\x80\x00\x01\x10\x01\x10\x00\x00J\xff\x80\x00\x02\x06string\x0c\x0a\x00\x08username\x06string\x0c\x0b\x00\x09diffusion\x06string\x0c\x09\x00\x07user_id\x06uint64\x06\x04\x00\xfe\xfa\xd7")

	// 准备一个 Map 或者 Struct 来接收数据
	// 鉴于 session 可能包含动态 key，用 map[interface{}]interface{} 最通用
	var data = make(map[interface{}]interface{})

	buf := bytes.NewBuffer(rawData)
	dec := gob.NewDecoder(buf)

	err := dec.Decode(&data)
	if err != nil {
		log.Fatal("Decoding failed:", err)
	}

	fmt.Printf("Parsed result: %+v\n", data)
	fmt.Printf("Value: %v, Type: %T\n", data["user_id"], data["user_id"])
	fmt.Printf("Value: %v, Type: %T\n", data["username"], data["username"])
}

func main() {
	// 1. 设置你的配置（来自于config.yaml的session_secret）
	hashKey := []byte("dev-session-secret") 
	
	// 2. 初始化 SecureCookie（第二个参数是加密 Key，通常为 nil，因为 session 只做签名验证）
	var s = securecookie.New(hashKey, nil)

	// 3. 从浏览器获取的完整 Cookie 值
	cookie_string := "linux_do_credit_session_id=MTc2NjUyMTA5MnxOd3dBTkVjME1qSlNRMUpLV0ZsSVdWQkdSRmxLUWxSRlFVVlJTMHhETWpWWFRWVkdXVkZJVERSTlIwdExTRXRYUVUwM1ZrWkhUa0U9fHaH5vFlte3L2fWJD9M2dNBtSynDLqnynvRttYrBHp4t"

	// 4. 提取 Cookie 值部分
	parts := securecookie.Split(cookie_string)
	if len(parts) != 2 {
		fmt.Println("Invalid cookie format")
		return
	}
	cookieName := parts[0]
	cookieValue := parts[1]

	var sessionID string
	err := s.Decode(cookieName, cookieValue, &sessionID)

	if err != nil {
		fmt.Printf("Failed to verify: %v\n", err)
		fmt.Println("Possible reasons: 1. SECRET is incorrect; 2. Cookie name is incorrect; 3. SECRET needs Hex decoding")
		return
	}

	fmt.Println("Verification successful!")
	fmt.Printf("Session ID parsed from Cookie: %s\n", sessionID)
	// 例如输出: G422RCRJXYHYPFDYJBTEAEQKLC25WMUFYQHL4MGKKHKWAM7VFGNA

	// redis使用
	// SELECT 0
	// GET "credit:session:G422RCRJXYHYPFDYJBTEAEQKLC25WMUFYQHL4MGKKHKWAM7VFGNA"
	// 然后把返回的值反序列化输出即可
}
```

文件`gen_user_cookie.go`内容如下：  
```go
package main

import (
	"bytes"
	"encoding/gob"
	"fmt"
	"log"
	"strings"

	"github.com/gorilla/securecookie"
)

func main() {
	// --- 1. CONFIGURATION ---
	// Replace with your actual hex or string secret
	sessionSecret := "dev-session-secret" 
	cookieName := "linux_do_credit_session_id"
	
	// Target User Data
	targetUsername := "diffusion"
	targetUserID := uint64(64215) // Change this to your target user's ID

	// --- 2. GENERATE SESSION ID ---
	// Typically a 32-character or 64-character hex string
	sessionID := fmt.Sprintf("%X", securecookie.GenerateRandomKey(24))

	// --- 3. GENERATE REDIS VALUE (GOB ENCODING) ---
	// We use map[interface{}]interface{} to match the observed binary pattern
	gob.Register(map[interface{}]interface{}{})
	data := map[interface{}]interface{}{
		"username": targetUsername,
		"user_id":  targetUserID,
	}

	var buf bytes.Buffer
	enc := gob.NewEncoder(&buf)
	if err := enc.Encode(&data); err != nil {
		log.Fatal("Encoding error:", err)
	}

	// Format as Redis-compatible escaped hex
	var redisValue strings.Builder
	for _, b := range buf.Bytes() {
		redisValue.WriteString(fmt.Sprintf("\\x%02x", b))
	}

	// --- 4. GENERATE SIGNED COOKIE STRING ---
	// Note: If secret is hex, use hex.DecodeString(sessionSecret)
	s := securecookie.New([]byte(sessionSecret), nil)
	encodedCookie, err := s.Encode(cookieName, sessionID)
	if err != nil {
		log.Fatal("Cookie signing error:", err)
	}

	// --- 5. OUTPUT ---
	fmt.Println("==================== GENERATED DATA ====================")
	fmt.Printf("Generated SESSION_ID: %s\n\n", sessionID)

	fmt.Println("--- RUN THIS IN REDIS-CLI ---")
	fmt.Printf("SET \"credit:session:%s\" \"%s\"\n", sessionID, redisValue.String())
	fmt.Printf("EXPIRE \"credit:session:%s\" 86400\n\n", sessionID)

	fmt.Println("--- REPLACE THIS IN BROWSER COOKIES ---")
	fmt.Printf("%s=%s\n", cookieName, encodedCookie)
	fmt.Println("========================================================")
}
```
