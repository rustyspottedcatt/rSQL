"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[807],{1876:(e,n,r)=>{r.r(n),r.d(n,{assets:()=>l,contentTitle:()=>o,default:()=>u,frontMatter:()=>s,metadata:()=>i,toc:()=>c});const i=JSON.parse('{"id":"advanced-usage","title":"Advanced Usage","description":"This section demonstrates advanced applications of the rSQL module, showing how to integrate complex SQL-like operations into your Roblox game.","source":"@site/docs/advanced-usage.md","sourceDirName":".","slug":"/advanced-usage","permalink":"/rSQL/docs/advanced-usage","draft":false,"unlisted":false,"editUrl":"https://github.com/rustyspottedcatt/rSQL/edit/main/docs/advanced-usage.md","tags":[],"version":"current","sidebarPosition":4,"frontMatter":{"sidebar_position":4},"sidebar":"mySidebar","previous":{"title":"Basic Usage","permalink":"/rSQL/docs/basic-usage"},"next":{"title":"Templates","permalink":"/rSQL/docs/templates"}}');var a=r(4848),t=r(8453);const s={sidebar_position:4},o="Advanced Usage",l={},c=[{value:"Custom Data Manipulation",id:"custom-data-manipulation",level:2},{value:"Example: Bulk Data Update",id:"example-bulk-data-update",level:3},{value:"Error Handling with Promises",id:"error-handling-with-promises",level:2},{value:"Example: Query Execution with Error Handling",id:"example-query-execution-with-error-handling",level:3},{value:"Integrating with Profile Service",id:"integrating-with-profile-service",level:2},{value:"Example: Creating and Using Profiles",id:"example-creating-and-using-profiles",level:3},{value:"Advanced Query Composition",id:"advanced-query-composition",level:2},{value:"Example: Dynamic WHERE Clause",id:"example-dynamic-where-clause",level:3},{value:"Best Practices",id:"best-practices",level:2}];function d(e){const n={code:"code",h1:"h1",h2:"h2",h3:"h3",header:"header",hr:"hr",li:"li",p:"p",pre:"pre",strong:"strong",ul:"ul",...(0,t.R)(),...e.components};return(0,a.jsxs)(a.Fragment,{children:[(0,a.jsx)(n.header,{children:(0,a.jsx)(n.h1,{id:"advanced-usage",children:"Advanced Usage"})}),"\n",(0,a.jsxs)(n.p,{children:["This section demonstrates advanced applications of the ",(0,a.jsx)(n.code,{children:"rSQL"})," module, showing how to integrate complex SQL-like operations into your Roblox game."]}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsx)(n.h2,{id:"custom-data-manipulation",children:"Custom Data Manipulation"}),"\n",(0,a.jsxs)(n.p,{children:["Utilize ",(0,a.jsx)(n.code,{children:"rSQL"})," to handle intricate data operations, such as selective updates and dynamic queries."]}),"\n",(0,a.jsx)(n.h3,{id:"example-bulk-data-update",children:"Example: Bulk Data Update"}),"\n",(0,a.jsx)(n.p,{children:"Update player scores conditionally:"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-lua",children:'local query = "UPDATE Players SET Score = Score + 100 WHERE Score < 5000"\r\nconnection:query(query):andThen(function(result)\r\n    print("Scores updated successfully.")\r\nend):catch(function(err)\r\n    warn("Failed to update scores:", err)\r\nend)\n'})}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsx)(n.h2,{id:"error-handling-with-promises",children:"Error Handling with Promises"}),"\n",(0,a.jsxs)(n.p,{children:["Handle errors effectively using ",(0,a.jsx)(n.code,{children:"Promise"}),"-based patterns. This ensures you can catch and address issues promptly."]}),"\n",(0,a.jsx)(n.h3,{id:"example-query-execution-with-error-handling",children:"Example: Query Execution with Error Handling"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-lua",children:'connection:query("SELECT * FROM Players WHERE Age < 18")\r\n    :andThen(function(results)\r\n        for _, player in ipairs(results) do\r\n            print(player.Name, player.Age)\r\n        end\r\n    end)\r\n    :catch(function(err)\r\n        warn("Query failed:", err)\r\n    end)\n'})}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsx)(n.h2,{id:"integrating-with-profile-service",children:"Integrating with Profile Service"}),"\n",(0,a.jsxs)(n.p,{children:[(0,a.jsx)(n.code,{children:"rSQL"})," can interface with the Profile Service to handle player data seamlessly."]}),"\n",(0,a.jsx)(n.h3,{id:"example-creating-and-using-profiles",children:"Example: Creating and Using Profiles"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-lua",children:'local profilesTable = {} -- Simulated profile data\r\nlocal config = {\r\n    allowCreate = true,\r\n    allowInsert = true,\r\n    allowSelect = true,\r\n    allowUpdate = true,\r\n}\r\n\r\nrSQL:connectToProfileService(profilesTable, config):andThen(function(connection)\r\n    print("Connected to Profile Service.")\r\n\r\n    -- Create a table for profiles\r\n    connection:query("CREATE TABLE PlayerProfiles (Id INTEGER PRIMARY KEY, Name TEXT, Age INTEGER)")\r\n\r\n    -- Insert a new profile\r\n    connection:query("INSERT INTO PlayerProfiles (Id, Name, Age) VALUES (1, \'Carlos\', 25)")\r\n\r\n    -- Query profiles\r\n    connection:query("SELECT * FROM PlayerProfiles")\r\n        :andThen(function(results)\r\n            for _, profile in ipairs(results) do\r\n                print(profile.Name, profile.Age)\r\n            end\r\n        end)\r\n        :catch(function(err)\r\n            warn("Failed to fetch profiles:", err)\r\n        end)\r\nend):catch(function(err)\r\n    warn("Failed to connect to Profile Service:", err)\r\nend)\n'})}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsx)(n.h2,{id:"advanced-query-composition",children:"Advanced Query Composition"}),"\n",(0,a.jsx)(n.p,{children:"Construct dynamic queries programmatically based on runtime conditions."}),"\n",(0,a.jsx)(n.h3,{id:"example-dynamic-where-clause",children:"Example: Dynamic WHERE Clause"}),"\n",(0,a.jsx)(n.pre,{children:(0,a.jsx)(n.code,{className:"language-lua",children:'local ageLimit = 20\r\nlocal query = string.format("SELECT * FROM Players WHERE Age > %d", ageLimit)\r\nconnection:query(query):andThen(function(results)\r\n    for _, player in ipairs(results) do\r\n        print(player.Name, player.Age)\r\n    end\r\nend):catch(function(err)\r\n    warn("Query failed:", err)\r\nend)\n'})}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsx)(n.h2,{id:"best-practices",children:"Best Practices"}),"\n",(0,a.jsxs)(n.ul,{children:["\n",(0,a.jsxs)(n.li,{children:[(0,a.jsx)(n.strong,{children:"Validate Queries"}),": Ensure your queries are correctly formatted to avoid runtime errors."]}),"\n",(0,a.jsxs)(n.li,{children:[(0,a.jsx)(n.strong,{children:"Error Logging"}),": Use ",(0,a.jsx)(n.code,{children:"catch"})," blocks to log and debug issues."]}),"\n",(0,a.jsxs)(n.li,{children:[(0,a.jsx)(n.strong,{children:"Optimize Conditions"}),": Minimize data filtering in queries for better performance."]}),"\n"]}),"\n",(0,a.jsx)(n.hr,{}),"\n",(0,a.jsxs)(n.p,{children:["With these advanced techniques, you can leverage the full power of ",(0,a.jsx)(n.code,{children:"rSQL"})," to manage complex data operations in your Roblox game!"]})]})}function u(e={}){const{wrapper:n}={...(0,t.R)(),...e.components};return n?(0,a.jsx)(n,{...e,children:(0,a.jsx)(d,{...e})}):d(e)}},8453:(e,n,r)=>{r.d(n,{R:()=>s,x:()=>o});var i=r(6540);const a={},t=i.createContext(a);function s(e){const n=i.useContext(t);return i.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function o(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(a):e.components||a:s(e.components),i.createElement(t.Provider,{value:n},e.children)}}}]);