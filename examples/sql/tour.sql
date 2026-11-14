CREATE TABLE Players (UserId INTEGER PRIMARY KEY, Name TEXT NOT NULL, Team TEXT, Coins INTEGER DEFAULT 0);
INSERT INTO Players (UserId, Name, Team, Coins) VALUES (101, 'alice', 'red', 120), (102, 'bob', 'blue', 40), (103, 'carol', 'red', 75), (104, 'dave', 'green', 40);
UPDATE Players SET Coins = Coins + 25 WHERE UserId = 102;
SELECT Name, Coins FROM Players WHERE Coins >= 50 ORDER BY Coins DESC;
SELECT Team, COUNT(*) AS players, SUM(Coins) AS coins FROM Players GROUP BY Team ORDER BY coins DESC;
EXPLAIN SELECT * FROM Players WHERE UserId = 102;
SELECT Name FROM Players WHER Coins > 10;
