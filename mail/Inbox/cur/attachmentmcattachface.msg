Return-Path: <lobo@lerch.org>
Delivered-To: lobo@lerch.org
Received: from mail.eler.ch
	by mail.eler.ch with LMTP
	id mLU6K98I8GhCBwAAyA9pPg
	(envelope-from <lobo@lerch.org>)
	for <lobo@lerch.org>; Wed, 15 Oct 2025 20:49:35 +0000
Date: Wed, 15 Oct 2025 13:48:55 -0700
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=lerch.org; s=2023;
	t=1760561375;
	h=from:from:reply-to:subject:subject:date:date:message-id:message-id:
	 to:to:cc:mime-version:mime-version:content-type:content-type;
	bh=fK/8hI6FilkYWKOrKBjauM3coZWekxJWs7kueYzsykk=;
	b=ARh96zUwRhAoTOSvAwdf1758NnPijJZY1UH5umSuZvqLwQKTZpNUpgKOwqg1S84gcbVLCQ
	g9+6B3FS3EFfRcVwBCQ7AOX5SezMSeMZUWh0lXOA5COVpiTSsn5ZJrDqKo/4gn9DlZMNY2
	DKfCW19OcTScS5GqJ0X0cwiPhJVcC6XJccVUUPESm4eRMndu4cyRL9PesIPnUBM4bX3vZE
	r84srk5AaDd8R526x1qgZTK0ModoH/UrOEbOBgon/OKklnBelOaEwmMUlQszxV8dqCscJB
	bGNSYVPVFbDbzeqr47hQ4bGGpvvBqnNpvi/ZUAhMObqSUK6fm68ZTPwghm0SVA==
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=lerch.org; s=2023;
	t=1760561374;
	h=from:from:reply-to:subject:subject:date:date:message-id:message-id:
	 to:to:cc:mime-version:mime-version:content-type:content-type;
	bh=fK/8hI6FilkYWKOrKBjauM3coZWekxJWs7kueYzsykk=;
	b=gXz65hYYxys2vqNPzcCxCgPtKewLwSmnSkZGwnsnNIU7/AxQSMKY3w+Q5ZelzK0ApAARqn
	CvLpCajueXfrYyMcM3nMY/vysCTbpFAejCMzkOxQkEZ7XkioZx/o5PChmsBcrvB7MHXqSo
	mQBKxA3JpPTq4s13xmFwiAZxmxsOV0Ibddzn7OylrMTn5h8yMAtXs6bwIfyXnZLLLGiQWz
	oFrzFBr+9anwKsLLgT4LGMoRLrp9sLAmgf6c5WhuLxbqR2Khlxma3t+6MeW1yliqwgs7C2
	elut2+rvcLL0jVQeMD4ABjU4DeTyZHvqlZDiJRAKJ0e0wWpcWYU0/rSS5X0PuA==
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=lerch.org; s=2023;
	t=1760561373;
	h=from:from:reply-to:subject:subject:date:date:message-id:message-id:
	 to:to:cc:mime-version:mime-version:content-type:content-type;
	bh=fK/8hI6FilkYWKOrKBjauM3coZWekxJWs7kueYzsykk=;
	b=CkLb+hn4F61VPfutWVY6WrtNhUzLTyt0ek7eQw2uOqjvdsyctLEGSEotbaAlE2O7fygSBi
	RZ0xdxbEkwvmGR4BhBXDLopVJqDwOgcE3tmyZTmSNchGne8kKZrfnffWUxMXybLfbGjRrO
	W8mkDsrtGKESv2W/VrKhzb8LU0JS8LNMFBr6C4yaVxHYeljbzTLMAonjLpe4G/TSRdqJ/3
	n9sVk3S3icP0KPPPqiT1Qf4eZDR5A9kfe8ck9aKdG3SAAx/6RhOSi73UVvp/5MGROW0Nm8
	VWfgM/S2MwZwN327BMWPlh9lWEYGJmz6HkxZriSgzpA4g22ATWXjv8AAHPhFnA==
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=lerch.org; s=2023;
	t=1760561371;
	h=from:from:reply-to:subject:subject:date:date:message-id:message-id:
	 to:to:cc:mime-version:mime-version:content-type:content-type;
	bh=fK/8hI6FilkYWKOrKBjauM3coZWekxJWs7kueYzsykk=;
	b=eew4LpLzaFedigVWolli8Sc68l86F2IrsYnHfJ5INqv25iI4gkS935Zlg6kKMPzA090zNX
	Ne0QnLHb0zK8AXKBLVhvb7hCIdU1fACx+p+K6UhDc6uIQrqUo3Mesdin+XISTa7hvhaTWn
	vWpMsuPyu1+fBN8JMjpu/Fa0XWxhTH8eB5fDi3G/gDxoxRm/visTlSXURq8FcM8Z7wKW6O
	TM6cFrk5KP2luxkt+GItWdPKU5D/fMLcu4bTc3aWXQ9WJONpUlMD7Fr9c8btat5VnX/lxh
	F+3dHyiU9a+/H6H/0eFPBzCauMWU7Jl8wStOJMecxGtv+Rw0bl6qTyElTSPtbA==
From: Emil Lerch <lobo@lerch.org>
To: lobo@lerch.org
Subject: Attachment
Message-ID: <4n4wn5ogmkpcboi2ipxj3wnt5iqe6rcb5bv5jvtseya7k2yqmi@7drgod2d766o>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="6ecwttx4c7nftwnw"
Content-Disposition: inline


--6ecwttx4c7nftwnw
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline

Attached is an attachment for attachment needs. Please see attached attachment.

--6ecwttx4c7nftwnw
Content-Type: text/plain; charset=us-ascii
Content-Disposition: attachment; filename="a.txt"

xwininfo: Window id: 0x1eb (the root window) "i3"

  Root window id: 0x1eb (the root window) "i3"
  Parent window id: 0x0 (none)
     154 children:
     0x600071b "CanvasBlocker": ("Firefox" "LibreWolf")  127x47+2378+89  +2378+89
        2 children:
        0x6000a12 (has no name): ()  127x47+0+0  +2378+89
        0x600071c (has no name): ()  1x1+-1+-1  +2377+88
     0x60004bf "Firefox": ("Firefox" "LibreWolf")  298x402+2113+801  +2113+801

--6ecwttx4c7nftwnw--
