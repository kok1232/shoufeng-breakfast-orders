# 壽豐早點 Supabase 設定步驟

## 1. 建立資料表

1. 打開 Supabase 專案。
2. 進入 SQL Editor。
3. 開啟 `supabase-schema.sql`。
4. 整份貼上並執行。

這份 SQL 會建立：

- `group_orders`：團體訂單
- `order_people`：點餐人
- `order_items`：餐點明細
- 四個資料庫函式：建立訂單、讀取訂單、加入餐點、鎖單

## 2. 取得前端連線資訊

到 Supabase：

`Project Settings` → `API`

複製：

- Project URL
- anon public key

注意：不要使用 service role key。service role key 不能放在網頁裡。

## 3. 打開訂餐頁

開啟：

`shoufeng-supabase-order.html`

把 Project URL 和 anon public key 填進「Supabase 連線」，按「儲存連線」。

## 4. 建立團體訂單

主訂餐人填：

- 平日 / 假日菜單
- 取餐日期與時間
- 主訂餐人與電話
- 最低份數 / 最低金額
- 取餐方式與備註

按「建立訂餐連結」後，會得到像這樣的網址：

`shoufeng-supabase-order.html?order=AB12CD34`

把這個連結傳給大家即可。

## 5. 收單流程

每個人打開同一個訂餐連結後：

1. 填姓名
2. 選固定備註
3. 選餐點數量
4. 送出餐點

資料會寫進 Supabase，同一張訂單會即時彙總。

## 6. 截止鎖單

主訂餐人按「截止鎖單」，輸入建立訂單時填的電話。

鎖單後，客人不能再新增餐點。

## 7. 放到 GitHub Pages

可以把 `shoufeng-supabase-order.html` 改名成 `index.html` 後放到 GitHub Pages。

上線後的連結會像：

`https://你的帳號.github.io/專案名稱/?order=AB12CD34`

