let Prolog:Grammar:Tokens:"⟪" = <Prolog:Grammar:Tokens:"(">
let Prolog:Grammar:Tokens:"⟫" = <Prolog:Grammar:Tokens:")">
let Prolog:Grammar:Tokens:"⟦" = <Prolog:Grammar:Tokens:"[">
let Prolog:Grammar:Tokens:"⟧" = <Prolog:Grammar:Tokens:"]">
let Prolog:Grammar:Tokens:";" = <Prolog:Grammar:Tokens:",">
let Prolog:Grammar:Tokens:"=>" = <Prolog:Grammar:Tokens:":-">
let Prolog:Grammar:Tokens:".end" = <Prolog:Grammar:Tokens:".">
let Prolog:Grammar:Tokens:"%%" = <Prolog:Grammar:Tokens:"%">
let Prolog:Grammar:Tokens:anything = <Prolog:Grammar:Tokens:"_">
let "ask " = <"?-">

edge⟪'A.}'; bob⟫ .end
path⟪X; Y⟫ =>
    %% Fake ending: .end and ⟫
    edge⟪X; Y⟫ .end
ask path⟪'A.}'; Destination⟫ .end
ask Values = ⟦-7; 9⟧ .end
ask 'Uppercase' = X .end
independent⟪anything; anything⟫ .end
ask independent⟪left; right⟫ .end
ask 'anything' = X .end
